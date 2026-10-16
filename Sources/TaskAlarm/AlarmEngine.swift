import AppKit
import Observation
import SwiftUI

/// Watches the clock and decides when to give a heads-up, pop up, nag, escalate,
/// check in, and what mood the smiley should be in.
@MainActor
@Observable
final class AlarmEngine {
    let store: TaskStore
    let prefs: Prefs

    /// Coarse clock (updated every few seconds) that views use for relative labels.
    private(set) var now = Date()
    /// Tasks that are due now (or missed), in the order they're shown.
    private(set) var attentionIDs: [UUID] = []
    /// Tasks coming up soon that get a gentle heads-up card.
    private(set) var headsUpIDs: [UUID] = []
    /// Tasks where the user pressed "Done" and we're asking "really?".
    var confirming: Set<UUID> = []
    /// Increments whenever popups should shake.
    private(set) var shakeTick = 0
    private(set) var showCheckIn = false
    private(set) var mood: Mood = .happy
    private(set) var status: StatusLevel = .clear
    private(set) var statusLine = ""

    // Callbacks to AppKit controllers
    @ObservationIgnored var onMenuBarUpdate: ((Mood, StatusLevel, Int) -> Void)?
    @ObservationIgnored var onPanelVisibility: ((Bool) -> Void)?
    @ObservationIgnored var onCelebrate: (() -> Void)?
    @ObservationIgnored var onShake: (() -> Void)?
    @ObservationIgnored var onOpenList: (() -> Void)?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var known: Set<UUID> = []
    @ObservationIgnored private var knownHeadsUp: Set<UUID> = []
    @ObservationIgnored private var lastNag: [UUID: Date] = [:]
    @ObservationIgnored private var shownAt: [UUID: Date] = [:]
    @ObservationIgnored private var overdueAnnounced: Set<UUID> = []
    @ObservationIgnored private var lastCheckIn = Date()
    @ObservationIgnored private var celebrateUntil: Date?
    @ObservationIgnored private var panelVisible = false

    /// Non-persistent popups quietly tuck themselves away after this long.
    static let autoHideSeconds: TimeInterval = 30

    init(store: TaskStore, prefs: Prefs) {
        self.store = store
        self.prefs = prefs
    }

    func start() {
        tick()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // After sleep, re-evaluate immediately.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    // MARK: - Actions

    /// Called by "Done" buttons. Asks for confirmation when enabled.
    func requestDone(_ id: UUID, alwaysConfirm: Bool = false) {
        if prefs.confirmCompletion || alwaysConfirm {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { _ = confirming.insert(id) }
            Haptics.tap(.alignment)
        } else {
            complete(id)
        }
    }

    func cancelConfirm(_ id: UUID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { _ = confirming.remove(id) }
        Haptics.tap(.generic, sound: .tock)
    }

    func complete(_ id: UUID) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            confirming.remove(id)
            store.complete(id)
        }
        let anyLeftToday = store.openTasks.contains { t in
            guard let d = t.deadline else { return false }
            return d < Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
        }
        SoundEngine.shared.play(anyLeftToday ? .success : .allDone)
        if prefs.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        celebrateUntil = Date().addingTimeInterval(anyLeftToday ? 2.5 : 4)
        onCelebrate?()
        tick()
    }

    func reopen(_ id: UUID) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { store.reopen(id) }
        Haptics.tap(.generic, sound: .tock)
        tick()
    }

    func snooze(_ id: UUID, minutes: Int) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            confirming.remove(id)
            store.snooze(id, minutes: minutes)
        }
        SoundEngine.shared.play(.snooze)
        if prefs.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        tick()
    }

    /// Repeating tasks: skip this occurrence and move on to the next one.
    func skip(_ id: UUID) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            confirming.remove(id)
            store.skip(id)
        }
        SoundEngine.shared.play(.snooze)
        Haptics.tap(.alignment, sound: nil)
        tick()
    }

    /// "Got it" on a heads-up card.
    func acknowledgeHeadsUp(_ id: UUID) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { store.acknowledgeHeadsUp(id) }
        Haptics.tap(.alignment)
        tick()
    }

    func dismissCheckIn(openList: Bool) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showCheckIn = false }
        Haptics.tap()
        if openList { onOpenList?() }
        tick()
    }

    func triggerCheckIn() {
        lastCheckIn = Date()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { showCheckIn = true }
        SoundEngine.shared.play(.checkIn)
        tick()
    }

    /// Creates a task due right now so the user can see what a popup looks like.
    func sendTestAlert() {
        store.add(title: "Test reminder — tap Done to try it", due: Date(), hasTime: true)
        tick()
    }

    // MARK: - The heartbeat

    func tick() {
        let t = Date()
        if Int(t.timeIntervalSince1970) / 5 != Int(now.timeIntervalSince1970) / 5 {
            now = t
        }

        // Non-persistent mode: popups tuck away and come back later.
        if !prefs.persistentPopups {
            for id in attentionIDs where !confirming.contains(id) {
                if let shown = shownAt[id], t.timeIntervalSince(shown) >= Self.autoHideSeconds {
                    store.snooze(id, minutes: prefs.defaultSnooze)
                }
            }
        }

        let hour = prefs.allDayHour
        let due = store.tasks
            .filter { task in
                guard !task.isDone, let m = task.alertMoment(allDayHour: hour) else { return false }
                return m <= t
            }
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
        let ids = due.map(\.id)
        let idSet = Set(ids)

        // 1. Newly due tasks: cheerful chime (or alarm if already missed).
        let fresh = due.filter { !known.contains($0.id) }
        if !fresh.isEmpty {
            let missed = fresh.contains { $0.isOverdue(at: t) }
            SoundEngine.shared.play(missed ? .alarm : .chime)
            if missed {
                Haptics.buzz()
                bumpShake()
            } else if prefs.hapticsEnabled {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
            for task in fresh {
                lastNag[task.id] = t
                shownAt[task.id] = t
                if task.isOverdue(at: t) { overdueAnnounced.insert(task.id) }
            }
        }

        // 2. A waiting task just slipped past its deadline: warn loudly.
        var playedThisTick = !fresh.isEmpty
        for task in due where task.isOverdue(at: t) && !overdueAnnounced.contains(task.id) {
            overdueAnnounced.insert(task.id)
            lastNag[task.id] = t
            if !playedThisTick {
                SoundEngine.shared.play(.alarm)
                Haptics.buzz()
                bumpShake()
                playedThisTick = true
            }
        }

        // 3. Still ignored? Nag every few minutes, escalating once missed.
        let nag = TimeInterval(prefs.nagMinutes * 60)
        for task in due where !confirming.contains(task.id) {
            guard let last = lastNag[task.id], t.timeIntervalSince(last) >= nag else { continue }
            lastNag[task.id] = t
            if !playedThisTick {
                let overdue = task.isOverdue(at: t)
                SoundEngine.shared.play(overdue ? .alarm : .nudge)
                if overdue { Haptics.buzz() }
                bumpShake()
                playedThisTick = true
            }
        }

        // Forget state for tasks that no longer need attention.
        for id in known.subtracting(idSet) {
            lastNag[id] = nil
            shownAt[id] = nil
            overdueAnnounced.remove(id)
            confirming.remove(id)
        }
        known = idSet

        // 4. Gentle heads-up a few minutes before timed tasks.
        let upcoming = store.tasks
            .filter { !idSet.contains($0.id) && $0.wantsHeadsUp(at: t, minutes: prefs.headsUpMinutes) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        let upIDs = upcoming.map(\.id)
        if upcoming.contains(where: { !knownHeadsUp.contains($0.id) }) && !playedThisTick {
            SoundEngine.shared.play(.headsUp)
            if prefs.hapticsEnabled {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        knownHeadsUp = Set(upIDs)

        let spring = Animation.spring(response: 0.45, dampingFraction: 0.82)
        if ids != attentionIDs { withAnimation(spring) { attentionIDs = ids } }
        if upIDs != headsUpIDs { withAnimation(spring) { headsUpIDs = upIDs } }

        // 5. Friendly check-in when nothing else is going on.
        if prefs.checkInEnabled, ids.isEmpty, upIDs.isEmpty, !showCheckIn {
            let h = Calendar.current.component(.hour, from: t)
            if (9..<21).contains(h), t.timeIntervalSince(lastCheckIn) >= TimeInterval(prefs.checkInHours * 3600) {
                triggerCheckIn()
                return
            }
        }

        updateMood(at: t, attention: ids.count, headsUp: upIDs.count)

        let wantPanel = !ids.isEmpty || !upIDs.isEmpty || showCheckIn
        if wantPanel != panelVisible {
            panelVisible = wantPanel
            onPanelVisibility?(wantPanel)
        }
    }

    private func bumpShake() {
        shakeTick += 1
        onShake?()
    }

    private func updateMood(at t: Date, attention: Int, headsUp: Int) {
        let open = store.openTasks
        let overdue = open.filter { $0.isOverdue(at: t) }.count
        let soon = headsUp > 0 || open.contains { task in
            guard let dl = task.deadline, task.hasTime else { return false }
            return dl > t && dl.timeIntervalSince(t) < 3600
        }
        let endOfToday = Calendar.current.startOfDay(for: t).addingTimeInterval(86_400)
        let todayOpen = open.filter { ($0.deadline ?? .distantFuture) < endOfToday }.count

        let newStatus: StatusLevel = overdue > 0 ? .overdue : attention > 0 ? .alert : soon ? .soon : .clear

        // Always encouraging — only a real miss makes the smiley worried.
        var newMood: Mood
        switch newStatus {
        case .overdue: newMood = .worried
        case .alert: newMood = .excited
        case .soon: newMood = .eager
        case .clear: newMood = todayOpen > 0 ? .eager : .happy
        }
        if let c = celebrateUntil, c > t { newMood = .celebrating } else { celebrateUntil = nil }

        let line: String
        if overdue > 0 {
            line = overdue == 1 ? "1 task slipped — let's catch up!" : "\(overdue) tasks slipped — one at a time!"
        } else if attention > 0 {
            line = attention == 1 ? "It's time! Let's do this." : "\(attention) things are up now. Let's go!"
        } else if headsUp > 0 {
            line = "Something's coming up soon. You're ready!"
        } else if todayOpen > 0 {
            line = todayOpen == 1 ? "Just 1 thing left today — you've got this!" : "\(todayOpen) things for today — you've got this!"
        } else if open.isEmpty {
            line = "All clear. Enjoy it! ✨"
        } else {
            line = "Nothing left for today. Nice work!"
        }

        if newMood != mood { mood = newMood }
        if newStatus != status { status = newStatus }
        if line != statusLine { statusLine = line }

        let badge = prefs.showBadge ? max(overdue, attention) : 0
        onMenuBarUpdate?(newMood, newStatus, badge)
    }
}
