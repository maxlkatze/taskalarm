import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class Prefs {
    static let shared = Prefs()

    @ObservationIgnored private let d = UserDefaults.standard

    // Alerts
    var persistentPopups: Bool { didSet { d.set(persistentPopups, forKey: "persistentPopups") } }
    var confirmCompletion: Bool { didSet { d.set(confirmCompletion, forKey: "confirmCompletion") } }
    var headsUpMinutes: Int { didSet { d.set(headsUpMinutes, forKey: "headsUpMinutes") } }
    var defaultSnooze: Int { didSet { d.set(defaultSnooze, forKey: "defaultSnooze") } }
    var nagMinutes: Int { didSet { d.set(nagMinutes, forKey: "nagMinutes") } }
    var allDayHour: Int { didSet { d.set(allDayHour, forKey: "allDayHour") } }

    // Sound & haptics
    var soundsEnabled: Bool { didSet { d.set(soundsEnabled, forKey: "soundsEnabled") } }
    var volume: Double { didSet { d.set(volume, forKey: "volume") } }
    var hapticsEnabled: Bool { didSet { d.set(hapticsEnabled, forKey: "hapticsEnabled") } }
    var clickSounds: Bool { didSet { d.set(clickSounds, forKey: "clickSounds") } }

    // Check-ins
    var checkInEnabled: Bool { didSet { d.set(checkInEnabled, forKey: "checkInEnabled") } }
    var checkInHours: Int { didSet { d.set(checkInHours, forKey: "checkInHours") } }

    // Menu bar
    var showBadge: Bool { didSet { d.set(showBadge, forKey: "showBadge") } }

    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("TaskAlarm: launch at login failed: \(error)")
            }
        }
    }

    static let snoozeChoices = [5, 10, 15, 20, 25, 30]
    static let headsUpChoices = [0, 5, 10, 15, 30]
    static let nagChoices = [1, 2, 5, 10]
    static let checkInChoices = [1, 2, 3, 4]

    private init() {
        d.register(defaults: [
            "persistentPopups": true,
            "confirmCompletion": true,
            "headsUpMinutes": 5,
            "defaultSnooze": 10,
            "nagMinutes": 2,
            "allDayHour": 9,
            "soundsEnabled": true,
            "volume": 0.7,
            "hapticsEnabled": true,
            "clickSounds": true,
            "checkInEnabled": true,
            "checkInHours": 2,
            "showBadge": true,
        ])
        persistentPopups = d.bool(forKey: "persistentPopups")
        confirmCompletion = d.bool(forKey: "confirmCompletion")
        headsUpMinutes = d.integer(forKey: "headsUpMinutes")
        defaultSnooze = d.integer(forKey: "defaultSnooze")
        nagMinutes = d.integer(forKey: "nagMinutes")
        allDayHour = d.integer(forKey: "allDayHour")
        soundsEnabled = d.bool(forKey: "soundsEnabled")
        volume = d.double(forKey: "volume")
        hapticsEnabled = d.bool(forKey: "hapticsEnabled")
        clickSounds = d.bool(forKey: "clickSounds")
        checkInEnabled = d.bool(forKey: "checkInEnabled")
        checkInHours = d.integer(forKey: "checkInHours")
        showBadge = d.bool(forKey: "showBadge")
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
