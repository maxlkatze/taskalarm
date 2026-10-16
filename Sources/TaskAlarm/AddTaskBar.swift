import SwiftUI

/// The quick-add field: type naturally ("Gym every Mon 6pm"), or pick a date and repeat with one click.
struct AddTaskBar: View {
    @Environment(TaskStore.self) private var store
    @Environment(AlarmEngine.self) private var engine

    @State private var text = ""
    @State private var manualDate: Date?
    @State private var manualHasTime = true
    /// Repeat chosen from the menu; overrides a typed one.
    @State private var manualRecurrence: Recurrence?
    @State private var showPicker = false
    @State private var pickerDate = Date()
    @State private var pickerHasTime = true
    @State private var justAdded = 0
    @FocusState private var focused: Bool

    private var parsed: QuickParser.Result? { QuickParser.parse(text) }

    private var recurrence: Recurrence? { manualRecurrence ?? parsed?.recurrence }

    /// The date that will be used.
    private var effective: (date: Date, hasTime: Bool)? {
        if let manualDate { return (manualDate, manualHasTime) }
        if let p = parsed, let d = p.date { return (d, p.hasTime) }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.bounce, value: justAdded)

                TextField("Add a task… “Gym every Mon 6pm”", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .focused($focused)
                    .onSubmit(add)

                repeatMenu
                dueMenu
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Color.primary.opacity(focused ? 0.07 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(focused ? 0.55 : 0), lineWidth: 1.5)
            )
            .animation(.easeOut(duration: 0.15), value: focused)

            if effective != nil || recurrence != nil {
                chips
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }

            if showPicker {
                picker
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: effective?.date)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: recurrence)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showPicker)
        .onAppear { focused = true }
    }

    // MARK: Menus

    private var dueMenu: some View {
        Menu {
            Section("Due") {
                Button { setDue(hour: nil, daysFromNow: 0) } label: { Label("Today", systemImage: "sun.max") }
                Button { setDue(hour: 18, daysFromNow: 0) } label: { Label("This evening (18:00)", systemImage: "sunset") }
                Button { setDue(hour: 9, daysFromNow: 1) } label: { Label("Tomorrow morning (9:00)", systemImage: "sunrise") }
                Button { setDue(hour: nil, daysFromNow: 1) } label: { Label("Tomorrow", systemImage: "calendar") }
                Button { setDue(hour: nil, daysFromNow: daysUntilMonday()) } label: { Label("Next Monday", systemImage: "calendar.badge.clock") }
                Button {
                    manualDate = Date().addingTimeInterval(3600)
                    manualHasTime = true
                } label: { Label("In 1 hour", systemImage: "clock") }
                Button {
                    pickerDate = effective?.date ?? roundedHour()
                    pickerHasTime = effective?.hasTime ?? true
                    showPicker = true
                } label: { Label("Pick date & time…", systemImage: "calendar.circle") }
            }
            if effective != nil {
                Divider()
                Button(role: .destructive) { clearDate() } label: { Label("No due date", systemImage: "xmark.circle") }
            }
        } label: {
            Image(systemName: effective == nil ? "calendar" : "calendar.badge.checkmark")
                .font(.system(size: 14))
                .foregroundStyle(effective == nil ? Color.secondary : Theme.accent)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Set a due date or time")
    }

    private var repeatMenu: some View {
        Menu {
            Section("Repeat") {
                ForEach(Recurrence.presets, id: \.self) { r in
                    Button {
                        manualRecurrence = r
                        Haptics.tap(.alignment)
                        focused = true
                    } label: {
                        if recurrence == r { Label(r.label, systemImage: "checkmark") } else { Text(r.label) }
                    }
                }
            }
            Text("Tip: type “every Mon & Thu 6pm”")
            if recurrence != nil {
                Divider()
                Button(role: .destructive) { clearRepeat() } label: { Label("Don't repeat", systemImage: "xmark.circle") }
            }
        } label: {
            Image(systemName: "repeat")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(recurrence == nil ? Color.secondary : Theme.accent)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Make it a repeating task")
    }

    // MARK: Chips & picker

    private var chips: some View {
        HStack(spacing: 6) {
            if let eff = effective {
                Chip(icon: eff.hasTime ? "alarm" : "calendar",
                     text: eff.hasTime ? "\(DueFormat.day(eff.date, now: Date())), \(DueFormat.time(eff.date))" : DueFormat.day(eff.date, now: Date()),
                     onRemove: clearDate)
            }
            if let r = recurrence {
                Chip(icon: "repeat", text: r.label, onRemove: clearRepeat)
            }
            Spacer(minLength: 0)
            Text("↩ to add")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DatePicker("Date", selection: $pickerDate, displayedComponents: .date)
                    .datePickerStyle(.field)
                    .labelsHidden()
                if pickerHasTime {
                    DatePicker("Time", selection: $pickerDate, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.field)
                        .labelsHidden()
                }
                Spacer()
                Toggle("Time", isOn: $pickerHasTime)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            HStack {
                Button("Cancel") { showPicker = false }
                    .buttonStyle(SoftButtonStyle())
                Spacer()
                Button("Set") {
                    manualDate = pickerHasTime ? pickerDate : Calendar.current.startOfDay(for: pickerDate)
                    manualHasTime = pickerHasTime
                    showPicker = false
                    Haptics.tap(.alignment)
                    focused = true
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    // MARK: Logic

    private func add() {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let title = parsed?.title ?? raw
        let due = effective
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            _ = store.add(title: title, due: due?.date, hasTime: due?.hasTime ?? false, recurrence: recurrence)
        }
        SoundEngine.shared.play(.add)
        if Prefs.shared.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        justAdded += 1
        text = ""
        manualDate = nil
        manualRecurrence = nil
        showPicker = false
        engine.tick()
    }

    private func setDue(hour: Int?, daysFromNow: Int) {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: daysFromNow, to: cal.startOfDay(for: Date()))!
        if let hour {
            manualDate = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day)
            manualHasTime = true
        } else {
            manualDate = day
            manualHasTime = false
        }
        showPicker = false
        Haptics.tap(.alignment)
        focused = true
    }

    /// Removes the date (typed or picked) but keeps the rest of the text.
    private func clearDate() {
        if manualDate != nil {
            manualDate = nil
        } else if let p = parsed, p.recurrence == nil {
            text = p.title
        }
        Haptics.tap(.generic, sound: .tock)
    }

    private func clearRepeat() {
        manualRecurrence = nil
        if let p = parsed, p.recurrence != nil {
            // Drop the typed "every …" phrase so it doesn't come right back, but keep a typed time.
            text = p.title
            if p.hasTime, let d = p.date, manualDate == nil {
                manualDate = d
                manualHasTime = true
            }
        }
        Haptics.tap(.generic, sound: .tock)
    }

    private func daysUntilMonday() -> Int {
        let weekday = Calendar.current.component(.weekday, from: Date()) // 1 = Sunday
        let d = (9 - weekday) % 7
        return d == 0 ? 7 : d
    }

    private func roundedHour() -> Date {
        let cal = Calendar.current
        let next = Date().addingTimeInterval(3600)
        return cal.date(bySettingHour: cal.component(.hour, from: next), minute: 0, second: 0, of: next) ?? next
    }
}

struct Chip: View {
    var icon: String
    var text: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(text).font(.system(size: 11, weight: .medium)).lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .opacity(0.7)
            }
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.accent.opacity(0.12)))
    }
}
