import SwiftUI

struct TaskRow: View {
    @Environment(TaskStore.self) private var store
    @Environment(AlarmEngine.self) private var engine

    var task: TaskItem
    var onOpen: (UUID) -> Void

    @State private var hovering = false

    var body: some View {
        let now = engine.now
        let confirming = engine.confirming.contains(task.id)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                CheckCircle(done: task.isDone, pending: confirming, tint: tint(now)) {
                    if task.isDone { engine.reopen(task.id) }
                    else if confirming { engine.complete(task.id) }
                    else { engine.requestDone(task.id) }
                }
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .strikethrough(task.isDone, color: .secondary)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                        .lineLimit(2)

                    if task.dueDate != nil || task.recurrence != nil || !task.notes.isEmpty || task.snoozedUntil != nil {
                        meta(now: now)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Fixed-width trailing area so hovering never shifts the layout.
                ZStack(alignment: .trailing) {
                    if hovering && !confirming {
                        HStack(spacing: 2) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { store.delete(task.id) }
                                Haptics.tap(.generic, sound: .tock)
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(IconButtonStyle())
                                .help("Delete")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 14)
                        }
                        .transition(.opacity)
                    }
                }
                .frame(width: 44, alignment: .trailing)
            }

            if confirming {
                HStack(spacing: 8) {
                    Text("Really done?")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button("Not yet") { engine.cancelConfirm(task.id) }
                        .buttonStyle(SoftButtonStyle())
                    Button("Yes!") { engine.complete(task.id) }
                        .buttonStyle(PrimaryButtonStyle(tint: Theme.good))
                }
                .padding(.leading, 30)
                .padding(.top, 8)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.05 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .contextMenu { contextMenu }
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: confirming)
    }

    @ViewBuilder
    private func meta(now: Date) -> some View {
        HStack(spacing: 8) {
            if task.dueDate != nil {
                let overdue = task.isOverdue(at: now)
                HStack(spacing: 3) {
                    Image(systemName: overdue ? "exclamationmark.circle.fill" : (task.hasTime ? "clock" : "calendar"))
                    Text(DueFormat.label(for: task, now: now))
                }
                .foregroundStyle(task.isDone ? Color.secondary : tint(now))
            }
            if let r = task.recurrence {
                HStack(spacing: 3) {
                    Image(systemName: "repeat")
                    Text(r.label)
                }
                .foregroundStyle(.secondary)
            }
            if let s = task.snoozedUntil, s > now, !task.isDone {
                HStack(spacing: 3) {
                    Image(systemName: "zzz")
                    Text(DueFormat.time(s))
                }
                .foregroundStyle(.secondary)
                .help("Snoozed until \(DueFormat.time(s))")
            }
            if !task.notes.isEmpty && task.recurrence == nil {
                Text(task.notes)
                    .lineLimit(1)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 11))
        .lineLimit(1)
    }

    @ViewBuilder
    private var contextMenu: some View {
        if task.isDone {
            Button("Mark as not done") { engine.reopen(task.id) }
        } else {
            Button("Mark as done") { engine.complete(task.id) }
            Button("Open…") { open() }
            Menu("Move to") {
                Button("Today") { move(days: 0) }
                Button("Tomorrow") { move(days: 1) }
                Button("Next week") { move(days: 7) }
                Divider()
                Button("No due date") {
                    var t = task; t.dueDate = nil; store.update(t)
                }
            }
            if task.recurrence != nil {
                Button("Skip this time") { engine.skip(task.id) }
            }
            if task.dueDate != nil {
                Menu("Remind me again in") {
                    ForEach(Prefs.snoozeChoices, id: \.self) { m in
                        Button("\(m) minutes") { engine.snooze(task.id, minutes: m) }
                    }
                }
            }
        }
        Button("Duplicate") { withAnimation { store.duplicate(task.id) } }
        Divider()
        Button("Delete", role: .destructive) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { store.delete(task.id) }
        }
    }

    private func open() {
        Haptics.tap(.alignment)
        onOpen(task.id)
    }

    private func tint(_ now: Date) -> Color {
        if task.isDone { return Theme.good }
        if task.isOverdue(at: now) { return Theme.bad }
        if let dl = task.deadline, task.hasTime, dl.timeIntervalSince(now) < 3600 { return Theme.warn }
        if let d = task.dueDate, Calendar.current.isDateInToday(d) { return Theme.accent }
        return .secondary
    }

    private func move(days: Int) {
        let cal = Calendar.current
        let base = cal.date(byAdding: .day, value: days, to: Date())!
        var target = cal.startOfDay(for: base)
        if task.hasTime, let old = task.dueDate {
            let c = cal.dateComponents([.hour, .minute], from: old)
            target = cal.date(bySettingHour: c.hour ?? 9, minute: c.minute ?? 0, second: 0, of: base) ?? target
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            store.reschedule(task.id, to: target, hasTime: task.dueDate == nil ? false : task.hasTime)
        }
        Haptics.tap(.alignment)
        engine.tick()
    }
}

/// The round checkbox. Fills with green and draws a checkmark.
struct CheckCircle: View {
    var done: Bool
    var pending: Bool
    var tint: Color
    var action: () -> Void

    @State private var hovering = false
    @State private var tap = 0

    var body: some View {
        Button(action: { tap += 1; action() }) {
            ZStack {
                Circle()
                    .strokeBorder(done || pending ? Theme.good : tint.opacity(0.7), lineWidth: 1.6)
                Circle()
                    .fill(done ? Theme.good : (pending ? Theme.good.opacity(0.18) : .clear))
                    .padding(done ? 0 : 3)
                CheckmarkShape()
                    .trim(from: 0, to: done ? 1 : (hovering || pending ? 1 : 0))
                    .stroke(done ? Color.white : Theme.good.opacity(pending ? 1 : 0.6),
                            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .padding(5)
            }
            .frame(width: 19, height: 19)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyframeAnimator(initialValue: 1.0, trigger: tap) { v, s in v.scaleEffect(s) } keyframes: { _ in
            SpringKeyframe(0.75, duration: 0.08)
            SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
        }
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: done)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .animation(.easeOut(duration: 0.18), value: pending)
        .help(done ? "Mark as not done" : "Mark as done")
    }
}

struct CheckmarkShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.55))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.42, y: r.minY + r.height * 0.82))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.9, y: r.minY + r.height * 0.18))
        return p
    }
}
