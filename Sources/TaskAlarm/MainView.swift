import SwiftUI

struct MainView: View {
    @Environment(TaskStore.self) private var store
    @Environment(AlarmEngine.self) private var engine
    enum Route: Equatable { case list, settings, task(UUID) }
    @State private var route: Route = .list

    var body: some View {
        ZStack {
            switch route {
            case .list:
                TaskListView(onSettings: { route = .settings }, onOpen: { route = .task($0) })
                    .transition(.move(edge: .leading).combined(with: .opacity))
            case .settings:
                SettingsView(onClose: { route = .list })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .task(let id):
                TaskDetailView(taskID: id, onClose: { route = .list })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: route)
        .frame(width: 360, height: 560)
        .clipped()
        .tint(Theme.accent)
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in route = .settings }
        // Start fresh on the list every time the popover opens again.
        .onReceive(NotificationCenter.default.publisher(for: .popoverClosed)) { _ in
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { route = .list }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTask)) { note in
            if let id = note.object as? UUID { route = .task(id) }
        }
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("TaskAlarm.openSettings")
    static let openTask = Notification.Name("TaskAlarm.openTask")
    static let popoverClosed = Notification.Name("TaskAlarm.popoverClosed")
}

private struct TaskSection: Identifiable {
    let id: String
    let title: String
    let color: Color
    let tasks: [TaskItem]
}

struct TaskListView: View {
    @Environment(TaskStore.self) private var store
    @Environment(AlarmEngine.self) private var engine
    var onSettings: () -> Void
    var onOpen: (UUID) -> Void

    @State private var showDone = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            AddTaskBar()
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            Divider().opacity(0.5)

            if store.tasks.isEmpty {
                emptyState
            } else {
                list
            }

            Divider().opacity(0.5)
            footer
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            SmileyView(mood: engine.mood, size: 44)
                .onTapGesture {
                    Haptics.tap(.levelChange, sound: .checkIn)
                }
                .help("Hi! 👋")
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                HStack(spacing: 5) {
                    Circle()
                        .fill(engine.status.color)
                        .frame(width: 7, height: 7)
                    Text(engine.statusLine)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                .animation(.easeOut(duration: 0.25), value: engine.statusLine)
            }
            Spacer()
            Button(action: { Haptics.tap(); onSettings() }) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(IconButtonStyle())
            .help("Settings")
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: engine.now)
        switch h {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Hello, night owl"
        }
    }

    // MARK: List

    private var sections: [TaskSection] {
        let now = engine.now
        let cal = Calendar.current
        let open = store.openTasks.sorted { a, b in
            switch (a.deadline, b.deadline) {
            case let (x?, y?): return x < y
            case (nil, nil): return a.createdAt < b.createdAt
            case (nil, _): return false
            case (_, nil): return true
            }
        }
        let overdue = open.filter { $0.isOverdue(at: now) }
        let rest = open.filter { !$0.isOverdue(at: now) }
        let today = rest.filter { $0.dueDate.map(cal.isDateInToday) ?? false }
        let tomorrow = rest.filter { $0.dueDate.map(cal.isDateInTomorrow) ?? false }
        let later = rest.filter { t in
            guard let d = t.dueDate else { return false }
            return !cal.isDateInToday(d) && !cal.isDateInTomorrow(d)
        }
        let someday = rest.filter { $0.dueDate == nil }

        return [
            TaskSection(id: "overdue", title: "Overdue", color: Theme.bad, tasks: overdue),
            TaskSection(id: "today", title: "Today", color: Theme.accent, tasks: today),
            TaskSection(id: "tomorrow", title: "Tomorrow", color: .secondary, tasks: tomorrow),
            TaskSection(id: "later", title: "Upcoming", color: .secondary, tasks: later),
            TaskSection(id: "someday", title: "Anytime", color: .secondary, tasks: someday),
        ].filter { !$0.tasks.isEmpty }
    }

    private var doneTasks: [TaskItem] {
        store.tasks.filter(\.isDone)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if sections.isEmpty {
                    allDoneBanner
                }
                ForEach(sections) { section in
                    sectionHeader(section.title, count: section.tasks.count, color: section.color)
                    ForEach(section.tasks) { task in
                        TaskRow(task: task, onOpen: onOpen)
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                    removal: .opacity.combined(with: .scale(scale: 0.95))))
                    }
                }

                if !doneTasks.isEmpty {
                    doneHeader
                    if showDone {
                        ForEach(doneTasks.prefix(30)) { task in
                            TaskRow(task: task, onOpen: onOpen)
                                .transition(.opacity)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.tasks)
        }
        .scrollIndicators(.never)
    }

    private func sectionHeader(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold))
                .textCase(.uppercase)
                .kerning(0.7)
                .foregroundStyle(color)
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private var doneHeader: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showDone.toggle() }
                Haptics.tap()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(showDone ? 90 : 0))
                    Text("Done")
                        .font(.system(size: 10.5, weight: .bold))
                        .textCase(.uppercase)
                        .kerning(0.7)
                    Text("\(doneTasks.count)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
                .foregroundStyle(Theme.good)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            if showDone {
                Button("Clear") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { store.clearCompleted() }
                    Haptics.tap(.generic, sound: .tock)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    private var allDoneBanner: some View {
        HStack(spacing: 10) {
            Text("🎉").font(.system(size: 22))
            VStack(alignment: .leading, spacing: 2) {
                Text("All done!").font(.system(size: 13, weight: .semibold))
                Text("Every task is checked off. Nice work.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.good.opacity(0.1)))
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            SmileyView(mood: .happy, size: 64)
            Text("Nothing on your plate")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text("Type above and press ↩.\nAdd a time and I'll make sure you don't miss it.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        let doneToday = store.tasks.filter { t in
            t.isDone && (t.completedAt.map(Calendar.current.isDateInToday) ?? false)
        }.count
        return HStack(spacing: 8) {
            Text(doneToday == 0 ? "\(store.openTasks.count) open" : "\(store.openTasks.count) open · \(doneToday) done today")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.snappy, value: doneToday)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(IconButtonStyle())
            .help("Quit TaskAlarm (reminders stop until you open it again)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}
