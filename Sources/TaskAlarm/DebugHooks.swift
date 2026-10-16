#if DEBUG
import Foundation

/// Debug builds only: drive the UI from the command line by posting the distributed
/// notification "app.taskalarm.debug" with a command string such as "done-first" or "test".
@MainActor
enum DebugHooks {
    static func install(engine: AlarmEngine, openList: @escaping () -> Void, closeList: @escaping () -> Void, settings: @escaping () -> Void) {
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("app.taskalarm.debug"), object: nil, queue: .main) { note in
            let cmd = note.object as? String ?? ""
            MainActor.assumeIsolated {
                let first = engine.attentionIDs.first
                switch cmd {
                case "done-first": if let first { engine.requestDone(first, alwaysConfirm: true) }
                case "confirm-first": if let first { engine.complete(first) }
                case "snooze-first": if let first { engine.snooze(first, minutes: 5) }
                case "checkin": engine.triggerCheckIn()
                case "test": engine.sendTestAlert()
                case "open": openList()
                case "close": closeList()
                case "settings": settings()
                case "detail":
                    openList()
                    if let id = engine.store.openTasks.first(where: { $0.recurrence != nil })?.id ?? engine.store.openTasks.first?.id {
                        NotificationCenter.default.post(name: .openTask, object: id)
                    }
                default: break
                }
            }
        }
    }
}
#endif
