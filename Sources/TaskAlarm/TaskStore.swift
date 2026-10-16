import Foundation
import Observation

/// Owns the task list and persists it as JSON in Application Support.
@MainActor
@Observable
final class TaskStore {
    private(set) var tasks: [TaskItem] = []

    @ObservationIgnored private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TaskAlarm", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("tasks.json")
        load()
    }

    // MARK: Queries

    func task(_ id: UUID) -> TaskItem? { tasks.first { $0.id == id } }

    var openTasks: [TaskItem] { tasks.filter { !$0.isDone } }

    // MARK: Mutations

    @discardableResult
    func add(title: String, notes: String = "", due: Date?, hasTime: Bool, recurrence: Recurrence? = nil) -> TaskItem {
        var due = due
        var hasTime = hasTime
        // A repeating task needs a start date: default to today (all-day), on a matching day.
        if let r = recurrence {
            if due == nil {
                due = Calendar.current.startOfDay(for: Date())
                hasTime = false
            }
            due = r.aligned(due!)
            // "every day 8:30" typed at 9:00 starts tomorrow, not overdue.
            if hasTime, let d = due, d < Date() { due = r.next(after: d) }
        }
        let item = TaskItem(title: title, notes: notes, dueDate: due, hasTime: due == nil ? true : hasTime,
                            recurrence: recurrence)
        tasks.append(item)
        save()
        return item
    }

    func update(_ item: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == item.id }) else { return }
        var new = item
        let old = tasks[i]
        // Changing the due date restarts the reminder cycle.
        if old.dueDate != new.dueDate || old.hasTime != new.hasTime {
            new.snoozedUntil = nil
        }
        if new.dueDate == nil { new.recurrence = nil }
        tasks[i] = new
        save()
    }

    /// Marks a task as done. Repeating tasks spawn their next occurrence.
    func complete(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].isDone = true
        tasks[i].completedAt = Date()
        tasks[i].snoozedUntil = nil
        let done = tasks[i]
        if let rule = done.recurrence, let due = done.dueDate {
            let next = rule.next(after: due)
            var copy = done
            copy.id = UUID()
            copy.isDone = false
            copy.completedAt = nil
            copy.createdAt = Date()
            copy.dueDate = next
            tasks.append(copy)
            // The finished one keeps its history but no longer repeats.
            tasks[i].recurrence = nil
        }
        save()
    }

    func acknowledgeHeadsUp(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].headsUpSeenFor = tasks[i].dueDate
        save()
    }

    /// Repeating tasks: jump to the next occurrence without marking this one done.
    func skip(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }),
              let rule = tasks[i].recurrence, let due = tasks[i].dueDate else { return }
        tasks[i].dueDate = rule.next(after: due)
        tasks[i].snoozedUntil = nil
        save()
    }

    func reopen(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].isDone = false
        tasks[i].completedAt = nil
        save()
    }

    func snooze(_ id: UUID, minutes: Int) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].snoozedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        save()
    }

    /// Moves the due date itself (e.g. "Move to tomorrow").
    func reschedule(_ id: UUID, to date: Date, hasTime: Bool) {
        guard var t = task(id) else { return }
        t.dueDate = date
        t.hasTime = hasTime
        update(t)
    }

    func duplicate(_ id: UUID) {
        guard var t = task(id) else { return }
        t.id = UUID()
        t.isDone = false
        t.completedAt = nil
        t.snoozedUntil = nil
        t.createdAt = Date()
        tasks.append(t)
        save()
    }

    func delete(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        save()
    }

    func clearCompleted() {
        tasks.removeAll { $0.isDone }
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let list = try? dec.decode([TaskItem].self, from: data) {
            tasks = list
        } else {
            // Keep a copy of an unreadable file instead of silently overwriting it.
            let backup = fileURL.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try enc.encode(tasks).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("TaskAlarm: could not save tasks: \(error)")
        }
    }
}
