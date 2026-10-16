import SwiftUI

struct SettingsView: View {
    @Environment(Prefs.self) private var prefs
    @Environment(AlarmEngine.self) private var engine
    var onClose: () -> Void

    var body: some View {
        @Bindable var prefs = prefs

        VStack(spacing: 0) {
            HStack {
                Button(action: { Haptics.tap(); onClose() }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(IconButtonStyle())
                .keyboardShortcut(.cancelAction)
                Text("Settings")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    group("Popups", icon: "rectangle.stack.badge.person.crop") {
                        toggle("Persistent popups", "Stay in the top-right corner until you confirm or snooze.", $prefs.persistentPopups)
                        toggle("Ask “Is it really done?”", "Double-check before ticking things off in the list too. Popups always ask.", $prefs.confirmCompletion)
                        picker("Heads-up before tasks", $prefs.headsUpMinutes, Prefs.headsUpChoices) { $0 == 0 ? "Off" : "\($0) min" }
                        picker("“Remind me in” default", $prefs.defaultSnooze, Prefs.snoozeChoices) { "\($0) min" }
                        picker("Repeat warnings every", $prefs.nagMinutes, Prefs.nagChoices) { "\($0) min" }
                        picker("All-day tasks pop up at", $prefs.allDayHour, Array(6...12)) { String(format: "%02d:00", $0) }
                    }

                    group("Sound & Haptics", icon: "speaker.wave.2") {
                        toggle("Sounds", "Cheerful when something's due, an alarm when it's missed.", $prefs.soundsEnabled)
                        if prefs.soundsEnabled {
                            HStack(spacing: 8) {
                                Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                                Slider(value: $prefs.volume, in: 0.1...1) { editing in
                                    if !editing { SoundEngine.shared.play(.chime) }
                                }
                                .controlSize(.small)
                                Image(systemName: "speaker.wave.3.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 6) {
                                preview("Due", .chime)
                                preview("Done", .success)
                                preview("Snooze", .snooze)
                                preview("Missed", .alarm)
                            }
                        }
                        toggle("Haptic feedback", "Feel taps on Force Touch trackpads.", $prefs.hapticsEnabled)
                        toggle("Click sounds", "Soft ticks when you tap things, like haptics you can hear.", $prefs.clickSounds)
                    }

                    group("Check-ins", icon: "hand.wave") {
                        toggle("Friendly check-ins", "A little hello now and then (9:00–21:00) when nothing else is going on.", $prefs.checkInEnabled)
                        if prefs.checkInEnabled {
                            picker("Every", $prefs.checkInHours, Prefs.checkInChoices) { $0 == 1 ? "hour" : "\($0) hours" }
                        }
                    }

                    group("General", icon: "gearshape") {
                        toggle("Show count in menu bar", "How many tasks need you right now.", $prefs.showBadge)
                        toggle("Open at login", "Start TaskAlarm automatically.", $prefs.launchAtLogin)
                        HStack(spacing: 8) {
                            Button {
                                engine.sendTestAlert()
                            } label: { Label("Test a popup", systemImage: "bell.badge") }
                                .buttonStyle(SoftButtonStyle())
                            Button {
                                engine.triggerCheckIn()
                            } label: { Label("Test a check-in", systemImage: "hand.wave") }
                                .buttonStyle(SoftButtonStyle())
                        }
                        .padding(.top, 2)
                    }

                    HStack(spacing: 8) {
                        SmileyView(mood: .happy, size: 20)
                        Text("TaskAlarm 1.0 · made with care")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)
        }
    }

    // MARK: Building blocks

    private func group<Content: View>(_ title: String, icon: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 10.5, weight: .bold))
                .textCase(.uppercase)
                .kerning(0.7)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Color.primary.opacity(0.045)))
        }
    }

    private func toggle(_ title: String, _ detail: String, _ value: Binding<Bool>) -> some View {
        Toggle(isOn: Binding(get: { value.wrappedValue }, set: { v in
            withAnimation(.spring(response: 0.3)) { value.wrappedValue = v }
            Haptics.tap(.alignment)
        })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private func picker(_ title: String, _ value: Binding<Int>, _ options: [Int], label: @escaping (Int) -> String) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            Picker(title, selection: value) {
                ForEach(options, id: \.self) { Text(label($0)).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private func preview(_ title: String, _ sound: SoundEngine.Sound) -> some View {
        Button {
            SoundEngine.shared.play(sound)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "play.fill").font(.system(size: 7))
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Play the “\(title)” sound")
    }
}
