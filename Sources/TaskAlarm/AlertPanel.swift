import AppKit
import SwiftUI

/// A borderless, always-on-top panel pinned to the top-right corner.
final class AlertPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Keeps the panel window perfectly still in the top-right corner. All motion happens
/// inside SwiftUI (cards fly in and out), so window resizes never fight the animation:
/// the window grows instantly before cards arrive and shrinks only after they've left.
@MainActor
final class AlertPanelController {
    private let panel: AlertPanel
    private let hosting: NSHostingView<AnyView>
    /// Offscreen copy of the card stack, used to measure the real height synchronously.
    private let probe: NSHostingController<AnyView>
    private var wanted = false
    /// True while the task list popover is open: popups step aside.
    private var suppressed = false
    private var onScreen = false
    private var contentHeight: CGFloat = 0
    private var shrinkWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?

    static let width: CGFloat = 372   // includes the shadow margin
    private let margin: CGFloat = 6
    /// Long enough for the SwiftUI removal transition to finish.
    private let settleDelay: TimeInterval = 0.5

    init(engine: AlarmEngine, store: TaskStore, prefs: Prefs) {
        panel = AlertPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        probe = NSHostingController(rootView: AnyView(
            AlertStackView(onHeight: { _ in })
                .environment(engine)
                .environment(store)
                .environment(prefs)
        ))
        probe.sizingOptions = []

        hosting = NSHostingView(rootView: AnyView(EmptyView()))
        hosting.sizingOptions = []
        panel.contentView = hosting

        hosting.rootView = AnyView(
            AlertStackView(onHeight: { [weak self] h in self?.setHeight(h) })
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .environment(engine)
                .environment(store)
                .environment(prefs)
        )

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyFrame() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyFrame() }
        }
    }

    func setVisible(_ show: Bool) {
        wanted = show
        update()
    }

    func setSuppressed(_ value: Bool) {
        suppressed = value
        update()
    }

    private func update() {
        let show = wanted && !suppressed
        hideWork?.cancel()
        if show {
            guard !onScreen || panel.alphaValue < 1 else { return }
            onScreen = true
            applyFrame()
            panel.orderFrontRegardless()
            // Re-measure once the window is actually on screen and laid out.
            DispatchQueue.main.async { [weak self] in self?.applyFrame() }
            if suppressed == false && panel.alphaValue < 1 {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    panel.animator().alphaValue = 1
                }
            }
        } else if onScreen {
            if suppressed {
                // Popover opened: fade out quickly, the cards stay where they are.
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.15
                    panel.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    MainActor.assumeIsolated { self?.finishHide() }
                })
            } else {
                // Last card left: let its SwiftUI exit transition play, then hide.
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated { self?.finishHide() }
                }
                hideWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: work)
            }
        }
    }

    private func finishHide() {
        guard !(wanted && !suppressed) else { return }
        onScreen = false
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    private func setHeight(_ h: CGFloat) {
        guard abs(h - contentHeight) > 0.5 else { return }
        let growing = h > contentHeight
        contentHeight = h
        shrinkWork?.cancel()
        if growing {
            applyFrame()   // instantly: content is top-aligned, so nothing visibly moves
        } else {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.applyFrame() }
            }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: work)
        }
    }

    private func applyFrame() {
        let screen = NSScreen.screens.first ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // The height preference can go stale when cards change while nothing is drawn
        // (e.g. a check-in firing while the display sleeps), so also measure directly.
        let measured = probe.sizeThatFits(in: CGSize(width: Self.width, height: 10_000)).height
        if measured > contentHeight { contentHeight = measured }
        let h = min(max(contentHeight, 40), vf.height - margin * 2)
        let frame = NSRect(x: vf.maxX - Self.width - margin, y: vf.maxY - h - margin, width: Self.width, height: h)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }
}

/// Cards slide in from the right with a soft spring the moment they appear.
private struct FlyIn: ViewModifier {
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .offset(x: shown ? 0 : 70)
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.94, anchor: .topTrailing)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { shown = true }
            }
    }
}

// MARK: - SwiftUI content

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct AlertStackView: View {
    @Environment(AlarmEngine.self) private var engine
    @Environment(TaskStore.self) private var store
    @Environment(Prefs.self) private var prefs
    var onHeight: (CGFloat) -> Void

    private let maxCards = 4

    var body: some View {
        let tasks = engine.attentionIDs.compactMap { store.task($0) }
        let upcoming = engine.headsUpIDs.compactMap { store.task($0) }
        VStack(alignment: .trailing, spacing: 10) {
            if engine.showCheckIn {
                CheckInCard()
                    .modifier(FlyIn())
                    .transition(.asymmetric(insertion: .identity,
                                            removal: .move(edge: .trailing).combined(with: .opacity)))
            }
            ForEach(tasks.prefix(maxCards)) { task in
                AlertCard(task: task)
                    .modifier(FlyIn())
                    .transition(.asymmetric(insertion: .identity,
                                            removal: .move(edge: .trailing).combined(with: .opacity)))
            }
            ForEach(upcoming.prefix(2)) { task in
                HeadsUpCard(task: task)
                    .modifier(FlyIn())
                    .transition(.asymmetric(insertion: .identity,
                                            removal: .move(edge: .trailing).combined(with: .opacity)))
            }
            if tasks.count > maxCards {
                MoreCard(count: tasks.count - maxCards)
                    .transition(.opacity)
            }
        }
        .padding(14)
        .frame(width: AlertPanelController.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { g in Color.clear.preference(key: HeightKey.self, value: g.size.height) })
        .onPreferenceChange(HeightKey.self) { h in onHeight(h) }
        .tint(Theme.accent)
    }
}

/// Shared card chrome: material background, rounded corners, soft shadow, colored edge.
private struct CardChrome: ViewModifier {
    var edge: Color
    var pulsing: Bool

    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                if pulsing {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(edge, lineWidth: 2)
                        .phaseAnimator([0.25, 1.0]) { v, phase in v.opacity(phase) } animation: { _ in .easeInOut(duration: 0.8) }
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(edge.opacity(0.55), lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
    }
}

/// Horizontal shake driven by a counter.
private struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        let progress = animatableData - animatableData.rounded(.down)
        let x = sin(progress * .pi * 6) * 7 * (1 - progress)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

struct AlertCard: View {
    @Environment(AlarmEngine.self) private var engine
    @Environment(Prefs.self) private var prefs
    var task: TaskItem

    var body: some View {
        let now = engine.now
        let overdue = task.isOverdue(at: now)
        let tint = overdue ? Theme.bad : Theme.warn
        let confirming = engine.confirming.contains(task.id)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                SmileyView(mood: confirming ? .celebrating : (overdue ? .worried : .excited), size: 38, color: tint)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: overdue ? "exclamationmark.triangle.fill" : "bell.fill")
                            .symbolEffect(.bounce, value: engine.shakeTick)
                        Text(overdue ? "Missed it?" : "It's time!")
                        if task.recurrence != nil {
                            Image(systemName: "repeat").help(task.recurrence?.label ?? "")
                        }
                    }
                    .font(.system(size: 10.5, weight: .bold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(tint)

                    Text(task.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle(now: now, overdue: overdue))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)

                    if !task.notes.isEmpty {
                        Text(task.notes)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if !prefs.persistentPopups && !confirming {
                    Button {
                        engine.snooze(task.id, minutes: prefs.defaultSnooze)
                    } label: { Image(systemName: "xmark") }
                        .buttonStyle(IconButtonStyle())
                        .help("Hide — I'll remind you in \(prefs.defaultSnooze) min")
                }
            }

            if confirming {
                confirmRow
                    .transition(.asymmetric(insertion: .push(from: .bottom), removal: .push(from: .top)).combined(with: .opacity))
            } else {
                actionRow
                    .transition(.asymmetric(insertion: .push(from: .top), removal: .push(from: .bottom)).combined(with: .opacity))
            }
        }
        .modifier(CardChrome(edge: tint, pulsing: overdue))
        .modifier(Shake(animatableData: CGFloat(engine.shakeTick)))
        .animation(.linear(duration: 0.55), value: engine.shakeTick)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            SnoozeMenu(taskID: task.id)
            Spacer()
            Button {
                engine.requestDone(task.id, alwaysConfirm: true)
            } label: {
                Label("Done", systemImage: "checkmark")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var confirmRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Is it really done? 🤔")
                .font(.system(size: 12.5, weight: .semibold))
            HStack(spacing: 8) {
                Button("Not yet") { engine.cancelConfirm(task.id) }
                    .buttonStyle(SoftButtonStyle())
                Spacer()
                Button {
                    engine.complete(task.id)
                } label: {
                    Label("Yes, it's done!", systemImage: "checkmark.seal.fill")
                }
                .buttonStyle(PrimaryButtonStyle(tint: Theme.good))
            }
        }
    }

    private func subtitle(now: Date, overdue: Bool) -> String {
        guard let d = task.dueDate, let dl = task.deadline else { return "" }
        if overdue {
            return task.hasTime
                ? "Was due at \(DueFormat.time(d)) · \(DueFormat.duration(now.timeIntervalSince(dl))) ago"
                : "Was due \(DueFormat.day(d, now: now).lowercased())"
        }
        if !task.hasTime { return "Due today" }
        if d > now { return "Due at \(DueFormat.time(d)) · in \(DueFormat.duration(d.timeIntervalSince(now)))" }
        return "Due now · \(DueFormat.time(d))"
    }
}

/// "Remind me in…" split button: click for the default, or pick 5–30 minutes.
struct SnoozeMenu: View {
    @Environment(AlarmEngine.self) private var engine
    @Environment(TaskStore.self) private var store
    @Environment(Prefs.self) private var prefs
    var taskID: UUID

    var body: some View {
        Menu {
            Section("Remind me again in…") {
                ForEach(Prefs.snoozeChoices, id: \.self) { m in
                    Button("\(m) minutes") { engine.snooze(taskID, minutes: m) }
                }
            }
            if let task = store.task(taskID), let rule = task.recurrence, let due = task.dueDate {
                Divider()
                Button {
                    engine.skip(taskID)
                } label: {
                    Label("Skip this time (next: \(DueFormat.day(rule.next(after: due), now: Date())))", systemImage: "forward.end")
                }
            }
        } label: {
            Label("Remind in \(prefs.defaultSnooze) min", systemImage: "alarm")
        } primaryAction: {
            engine.snooze(taskID, minutes: prefs.defaultSnooze)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .fixedSize()
        .help("Click to snooze for \(prefs.defaultSnooze) minutes, or use the arrow to choose")
    }
}

/// A gentle "coming up" card a few minutes before a timed task. No nagging, no alarm.
struct HeadsUpCard: View {
    @Environment(AlarmEngine.self) private var engine
    var task: TaskItem

    var body: some View {
        let now = engine.now
        let confirming = engine.confirming.contains(task.id)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                SmileyView(mood: confirming ? .celebrating : .eager, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text("Coming up")
                        if task.recurrence != nil { Image(systemName: "repeat") }
                    }
                    .font(.system(size: 10.5, weight: .bold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(Theme.accent)

                    Text(task.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if let d = task.dueDate {
                        Text("At \(DueFormat.time(d)) · in \(DueFormat.duration(max(60, d.timeIntervalSince(now))))")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if confirming {
                HStack(spacing: 8) {
                    Text("Already done? 🎉").font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Button("Not yet") { engine.cancelConfirm(task.id) }
                        .buttonStyle(SoftButtonStyle())
                    Button("Yes!") { engine.complete(task.id) }
                        .buttonStyle(PrimaryButtonStyle(tint: Theme.good))
                }
                .transition(.opacity)
            } else {
                HStack(spacing: 8) {
                    Button("Already done") { engine.requestDone(task.id, alwaysConfirm: true) }
                        .buttonStyle(SoftButtonStyle())
                    Spacer()
                    Button {
                        engine.acknowledgeHeadsUp(task.id)
                    } label: { Label("Got it", systemImage: "hand.thumbsup.fill") }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .transition(.opacity)
            }
        }
        .modifier(CardChrome(edge: Theme.accent, pulsing: false))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: confirming)
    }
}

struct CheckInCard: View {
    @Environment(AlarmEngine.self) private var engine
    @Environment(TaskStore.self) private var store
    @State private var greeting = ["How's it going? 👋", "Hey there! How are you doing?", "Quick hello! 😊", "Still on track?"]
        .randomElement()!

    var body: some View {
        let open = store.openTasks
        let endOfToday = Calendar.current.startOfDay(for: engine.now).addingTimeInterval(86_400)
        let today = open.filter { ($0.deadline ?? .distantFuture) < endOfToday }.count

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                SmileyView(mood: today == 0 ? .happy : .eager, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Just checking in")
                        .font(.system(size: 10.5, weight: .bold))
                        .textCase(.uppercase)
                        .kerning(0.6)
                        .foregroundStyle(Theme.accent)
                    Text(greeting)
                        .font(.system(size: 14, weight: .semibold))
                    Text(summary(open: open.count, today: today))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Button("Show my list") { engine.dismissCheckIn(openList: true) }
                    .buttonStyle(SoftButtonStyle())
                Spacer()
                Button {
                    engine.dismissCheckIn(openList: false)
                } label: { Label("All good!", systemImage: "hand.thumbsup.fill") }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .modifier(CardChrome(edge: Theme.accent, pulsing: false))
    }

    private func summary(open: Int, today: Int) -> String {
        if open == 0 { return "Your list is empty. Anything on your mind you'd like to note down?" }
        if today == 0 { return "Nothing left for today. You have \(open) open task\(open == 1 ? "" : "s") for later." }
        return "\(today) thing\(today == 1 ? "" : "s") left for today. Pick one and go — you've got this!"
    }
}

private struct MoreCard: View {
    @Environment(AlarmEngine.self) private var engine
    @Environment(Prefs.self) private var prefs
    var count: Int

    var body: some View {
        HStack {
            Text("+\(count) more waiting")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Show all") { engine.onOpenList?() }
                .buttonStyle(SoftButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }
}
