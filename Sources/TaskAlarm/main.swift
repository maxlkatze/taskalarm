import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let prefs = Prefs.shared
    private let store = TaskStore()
    private lazy var engine = AlarmEngine(store: store, prefs: prefs)
    private var statusItem: StatusItemController!
    private var panel: AlertPanelController!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController()
        statusItem.onLeftClick = { [weak self] in self?.togglePopover() }
        statusItem.onRightClick = { [weak self] button in self?.showMenu(from: button) }

        let root = MainView()
            .environment(store)
            .environment(engine)
            .environment(prefs)
        let host = NSHostingController(rootView: root)
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        panel = AlertPanelController(engine: engine, store: store, prefs: prefs)

        engine.onMenuBarUpdate = { [weak self] mood, status, badge in
            self?.statusItem.apply(mood: mood, status: status, badge: badge)
        }
        engine.onPanelVisibility = { [weak self] visible in self?.panel.setVisible(visible) }
        engine.onCelebrate = { [weak self] in self?.statusItem.bounce() }
        engine.onShake = { [weak self] in self?.statusItem.shake() }
        engine.onOpenList = { [weak self] in self?.showPopover() }
        engine.start()

        #if DEBUG
        DebugHooks.install(engine: engine,
                           openList: { [weak self] in self?.showPopover() },
                           closeList: { [weak self] in self?.popover.performClose(nil) },
                           settings: { NotificationCenter.default.post(name: .openSettings, object: nil) })
        #endif

        // First launch: say hello so people know where the app lives.
        if !UserDefaults.standard.bool(forKey: "didWelcome") {
            UserDefaults.standard.set(true, forKey: "didWelcome")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showPopover()
                SoundEngine.shared.play(.checkIn)
            }
        }
    }

    /// Opening the app again (Finder, Spotlight, Dock) shows the list.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        Haptics.tap(.alignment, sound: nil)
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open TaskAlarm", action: #selector(openFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Check in now", action: #selector(checkInFromMenu), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit TaskAlarm", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    func popoverWillShow(_ notification: Notification) { panel.setSuppressed(true) }
    func popoverDidClose(_ notification: Notification) {
        panel.setSuppressed(false)
        NotificationCenter.default.post(name: .popoverClosed, object: nil)
    }

    @objc private func openFromMenu() { showPopover() }
    @objc private func checkInFromMenu() { engine.triggerCheckIn() }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
