import SwiftUI

/// Full-page editor for one task. Slides in like Settings; changes save when you go back.
struct TaskDetailView: View {
    @Environment(TaskStore.self) private var store
    @Environment(AlarmEngine.self) private var engine

    let taskID: UUID
    var onClose: () -> Void

    @State private var draft: TaskItem?
    @State private var hasDate = false
    @State private var customRepeat = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if draft != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        titleSection
                        whenSection
                        if hasDate { repeatSection }
                        actions
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.never)
            } else {
                Spacer()
            }
        }
        .onAppear(perform: load)
        .onDisappear(perform: save)   // never lose edits, however the page is left
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Button(action: saveAndClose) { Image(systemName: "chevron.left") }
                .buttonStyle(IconButtonStyle())
                .keyboardShortcut(.cancelAction)
            Text("Task")
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Spacer()
            Button("Done", action: saveAndClose)
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var titleSection: some View {
        card {
            TextField("What needs doing?", text: binding(\.title))
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .focused($titleFocused)
            Divider().opacity(0.5)
            TextField("Notes", text: binding(\.notes), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .lineLimit(1...5)
        }
    }

    private var whenSection: some View {
        section("When", icon: "calendar") {
            Toggle(isOn: $hasDate.animation(.spring(response: 0.3, dampingFraction: 0.9))) {
                Text("Due date").font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if hasDate {
                HStack(spacing: 8) {
                    DatePicker("", selection: dateBinding, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.field)
                    if draft?.hasTime == true {
                        DatePicker("", selection: dateBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.field)
                    }
                    Spacer(minLength: 0)
                }
                Toggle(isOn: binding(\.hasTime).animation(.spring(response: 0.3, dampingFraction: 0.9))) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("At a specific time").font(.system(size: 13, weight: .medium))
                        Text("Off = any time that day (all-day)").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    private var repeatSection: some View {
        section("Repeat", icon: "repeat") {
            // Quick presets as pills
            FlowPills(selected: draft?.recurrence, custom: customRepeat) { choice in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    switch choice {
                    case .none: draft?.recurrence = nil; customRepeat = false
                    case .preset(let r): draft?.recurrence = r; customRepeat = false
                    case .custom:
                        customRepeat = true
                        if draft?.recurrence == nil { draft?.recurrence = Recurrence(unit: .week, weekdays: currentWeekday()) }
                    }
                }
                Haptics.tap(.alignment)
            }

            if customRepeat, let r = draft?.recurrence {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("Every").font(.system(size: 13, weight: .medium))
                        Stepper(value: recurrenceBinding(\.interval), in: 1...99) {
                            Text("\(r.interval)")
                                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                .frame(minWidth: 18)
                        }
                        Picker("", selection: recurrenceBinding(\.unit)) {
                            ForEach(Recurrence.Unit.allCases) { Text($0.name(r.interval)).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        Spacer(minLength: 0)
                    }
                    if r.unit == .week {
                        HStack(spacing: 5) {
                            ForEach(Recurrence.orderedWeekdays, id: \.self) { wd in
                                let on = r.weekdays.contains(wd)
                                Button {
                                    var set = r.weekdays
                                    if on { set.remove(wd) } else { set.insert(wd) }
                                    draft?.recurrence?.weekdays = set
                                    Haptics.tap(.alignment)
                                } label: {
                                    Text(Recurrence.initial(wd))
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .frame(width: 30, height: 30)
                                        .foregroundStyle(on ? .white : .primary)
                                        .background(Circle().fill(on ? Theme.accent : Color.primary.opacity(0.07)))
                                }
                                .buttonStyle(.plain)
                                .help(Recurrence.shortName(wd))
                            }
                        }
                    }
                }
                .transition(.opacity)
            }

            if let r = draft?.recurrence, let d = draft?.dueDate {
                let next = r.next(after: r.aligned(d), now: max(Date(), r.aligned(d)))
                Text("\(r.label) · next after this: \(DueFormat.day(next, now: Date()))\(draft?.hasTime == true ? ", \(DueFormat.time(next))" : "")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let t = draft, !t.isDone {
                HStack(spacing: 8) {
                    Button {
                        saveAndClose()
                        engine.complete(taskID)
                    } label: { Label("Mark done", systemImage: "checkmark") }
                        .buttonStyle(PrimaryButtonStyle(tint: Theme.good))
                    if t.recurrence != nil {
                        Button {
                            save()
                            engine.skip(taskID)
                            load()
                        } label: { Label("Skip this time", systemImage: "forward.end") }
                            .buttonStyle(SoftButtonStyle())
                    }
                }
            }
            HStack(spacing: 8) {
                Button {
                    save()
                    store.duplicate(taskID)
                    Haptics.tap()
                    onClose()
                } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    .buttonStyle(SoftButtonStyle())
                Spacer()
                Button(role: .destructive) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { store.delete(taskID) }
                    Haptics.tap(.generic, sound: .tock)
                    onClose()
                } label: {
                    Label("Delete", systemImage: "trash").foregroundStyle(Theme.bad)
                }
                .buttonStyle(SoftButtonStyle())
            }
        }
    }

    // MARK: Building blocks

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Color.primary.opacity(0.045)))
    }

    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 10.5, weight: .bold))
                .textCase(.uppercase)
                .kerning(0.7)
                .foregroundStyle(Theme.accent)
            card(content)
        }
    }

    // MARK: Data

    private func binding<V>(_ kp: WritableKeyPath<TaskItem, V>) -> Binding<V> {
        Binding(get: { draft![keyPath: kp] }, set: { draft?[keyPath: kp] = $0 })
    }

    private func recurrenceBinding<V>(_ kp: WritableKeyPath<Recurrence, V>) -> Binding<V> {
        Binding(get: { draft!.recurrence![keyPath: kp] }, set: { draft?.recurrence?[keyPath: kp] = $0 })
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { draft?.dueDate ?? defaultDate() }, set: { draft?.dueDate = $0 })
    }

    private func load() {
        guard let t = store.task(taskID) else { onClose(); return }
        draft = t
        hasDate = t.dueDate != nil
        if let r = t.recurrence { customRepeat = !Recurrence.presets.contains(r) }
        if t.title.isEmpty { titleFocused = true }
    }

    private func save() {
        guard var t = draft else { return }
        t.title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.title.isEmpty, let old = store.task(taskID) { t.title = old.title }
        if hasDate {
            var d = t.dueDate ?? defaultDate()
            if !t.hasTime { d = Calendar.current.startOfDay(for: d) }
            // A weekday rule like "Mon & Thu" starts on the first matching day.
            if let r = t.recurrence { d = r.aligned(d) }
            t.dueDate = d
        } else {
            t.dueDate = nil
            t.recurrence = nil
        }
        if t != store.task(taskID) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { store.update(t) }
        }
        draft = t
        engine.tick()
    }

    private func saveAndClose() {
        save()
        Haptics.tap(.alignment)
        onClose()
    }

    private func defaultDate() -> Date {
        let cal = Calendar.current
        let next = Date().addingTimeInterval(3600)
        return cal.date(bySettingHour: cal.component(.hour, from: next), minute: 0, second: 0, of: next) ?? next
    }

    private func currentWeekday() -> Set<Int> {
        [Calendar.current.component(.weekday, from: draft?.dueDate ?? Date())]
    }
}

/// Wrapping row of repeat presets.
private struct FlowPills: View {
    enum Choice { case none, preset(Recurrence), custom }
    var selected: Recurrence?
    var custom: Bool
    var onSelect: (Choice) -> Void

    var body: some View {
        let items: [(String, Choice, Bool)] =
            [("Never", .none, selected == nil)]
            + Recurrence.presets.map { ($0.label, Choice.preset($0), !custom && selected == $0) }
            + [("Custom…", .custom, custom)]
        WrapLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button { onSelect(item.1) } label: {
                    Text(item.0)
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(item.2 ? .white : .primary)
                        .background(Capsule().fill(item.2 ? Theme.accent : Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A simple left-to-right wrapping layout.
private struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
