import Foundation

/// How a task repeats: every N days / weeks / months / years, optionally only on
/// certain weekdays ("every workday", "every Mon & Thu").
struct Recurrence: Codable, Equatable, Hashable {
    enum Unit: String, Codable, CaseIterable, Identifiable {
        case day, week, month, year
        var id: String { rawValue }
        func name(_ n: Int) -> String {
            switch self {
            case .day: return n == 1 ? "day" : "days"
            case .week: return n == 1 ? "week" : "weeks"
            case .month: return n == 1 ? "month" : "months"
            case .year: return n == 1 ? "year" : "years"
            }
        }
    }

    var unit: Unit
    var interval: Int = 1
    /// Calendar weekdays (1 = Sunday … 7 = Saturday). Only used with `.week`; empty = same weekday as the due date.
    var weekdays: Set<Int> = []

    static let workdays: Set<Int> = [2, 3, 4, 5, 6]
    static let weekend: Set<Int> = [1, 7]

    // Presets shown in menus
    static let daily = Recurrence(unit: .day)
    static let everyWorkday = Recurrence(unit: .week, weekdays: workdays)
    static let weekends = Recurrence(unit: .week, weekdays: weekend)
    static let weekly = Recurrence(unit: .week)
    static let biweekly = Recurrence(unit: .week, interval: 2)
    static let monthly = Recurrence(unit: .month)
    static let yearly = Recurrence(unit: .year)
    static let presets: [Recurrence] = [.daily, .everyWorkday, .weekends, .weekly, .biweekly, .monthly, .yearly]

    var label: String {
        if unit == .week && interval == 1 {
            if weekdays == Self.workdays { return "Every workday" }
            if weekdays == Self.weekend { return "Weekends" }
            if weekdays.count == 7 { return "Every day" }
        }
        var base = interval == 1 ? "Every \(unit.name(1))" : "Every \(interval) \(unit.name(interval))"
        if unit == .week, !weekdays.isEmpty {
            let names = Self.orderedWeekdays.filter(weekdays.contains).map { Self.shortName($0) }
            base = interval == 1 ? "Every \(names.joined(separator: ", "))" : base + " on \(names.joined(separator: ", "))"
        }
        return base
    }

    /// Monday-first ordering, which reads naturally for most people.
    static let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1]

    static func shortName(_ weekday: Int) -> String {
        Calendar.current.shortWeekdaySymbols[weekday - 1].trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    static func initial(_ weekday: Int) -> String {
        Calendar.current.veryShortWeekdaySymbols[weekday - 1]
    }

    /// Whether `date` is a valid occurrence day for this rule.
    func matches(_ date: Date) -> Bool {
        guard unit == .week, !weekdays.isEmpty else { return true }
        return weekdays.contains(Calendar.current.component(.weekday, from: date))
    }

    /// First valid occurrence on or after `date` (keeps the time of day).
    func aligned(_ date: Date) -> Date {
        guard unit == .week, !weekdays.isEmpty else { return date }
        let cal = Calendar.current
        var d = date
        for _ in 0..<8 where !matches(d) { d = cal.date(byAdding: .day, value: 1, to: d)! }
        return d
    }

    /// The next occurrence after `date`, always in the future.
    func next(after date: Date, now: Date = Date()) -> Date {
        let cal = Calendar.current
        let n = max(1, interval)
        var d = date
        var guardCount = 0
        repeat {
            guardCount += 1
            switch unit {
            case .day: d = cal.date(byAdding: .day, value: n, to: d)!
            case .month: d = cal.date(byAdding: .month, value: n, to: d)!
            case .year: d = cal.date(byAdding: .year, value: n, to: d)!
            case .week:
                if weekdays.isEmpty {
                    d = cal.date(byAdding: .day, value: 7 * n, to: d)!
                } else {
                    d = nextWeekdayOccurrence(after: d, anchor: date, every: n)
                }
            }
        } while d <= now && guardCount < 10_000
        return d
    }

    private func nextWeekdayOccurrence(after d: Date, anchor: Date, every n: Int) -> Date {
        let cal = Calendar.current
        let anchorWeek = cal.dateInterval(of: .weekOfYear, for: anchor)?.start ?? anchor
        var c = d
        for _ in 0..<(7 * n + 7) {
            c = cal.date(byAdding: .day, value: 1, to: c)!
            guard matches(c) else { continue }
            let week = cal.dateInterval(of: .weekOfYear, for: c)?.start ?? c
            let weeks = (cal.dateComponents([.day], from: anchorWeek, to: week).day ?? 0) / 7
            if weeks % n == 0 { return c }
        }
        return c
    }
}

struct TaskItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var notes: String = ""
    var dueDate: Date?
    /// When false the task is due "some time that day" (an all-day task).
    var hasTime: Bool = true
    var recurrence: Recurrence?
    var isDone = false
    var completedAt: Date?
    var createdAt = Date()
    /// Set by "Remind me in…" — the popup comes back at this moment.
    var snoozedUntil: Date?
    /// The due date whose heads-up was already acknowledged (so it shows once per occurrence).
    var headsUpSeenFor: Date?

    /// The moment a task counts as overdue.
    var deadline: Date? {
        guard let d = dueDate else { return nil }
        if hasTime { return d }
        return Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: d)
    }

    /// When the "It's time!" popup should appear.
    func alertMoment(allDayHour: Int) -> Date? {
        if let s = snoozedUntil { return s }
        guard let d = dueDate else { return nil }
        if hasTime { return d }
        return Calendar.current.date(bySettingHour: allDayHour, minute: 0, second: 0, of: d)
    }

    /// Whether a gentle "coming up" heads-up should show right now.
    func wantsHeadsUp(at now: Date, minutes: Int) -> Bool {
        guard minutes > 0, !isDone, hasTime, snoozedUntil == nil, let d = dueDate else { return false }
        guard headsUpSeenFor != d else { return false }
        return now >= d.addingTimeInterval(TimeInterval(-minutes * 60)) && now < d
    }

    /// A timed task only counts as missed after a short grace period,
    /// so "it's time!" gets a friendly chime before any alarm.
    static let grace: TimeInterval = 5 * 60

    func isOverdue(at now: Date) -> Bool {
        guard !isDone, let dl = deadline else { return false }
        return now > dl.addingTimeInterval(hasTime ? Self.grace : 0)
    }
}

// MARK: - Human friendly formatting

enum DueFormat {
    /// "2h 5m", "25 min", "3 days"
    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(abs(seconds))
        if s < 60 { return "less than a minute" }
        let m = s / 60
        if m < 60 { return "\(m) min" }
        let h = m / 60
        if h < 24 { return m % 60 == 0 ? "\(h)h" : "\(h)h \(m % 60)m" }
        let d = h / 24
        return d == 1 ? "1 day" : "\(d) days"
    }

    static func time(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }

    /// Short label for list rows: "Today 14:00", "Tomorrow", "Fri 9:00", "24 Oct".
    static func label(for task: TaskItem, now: Date) -> String {
        guard let d = task.dueDate else { return "" }
        let cal = Calendar.current
        if task.isOverdue(at: now), let dl = task.deadline {
            return task.hasTime ? "\(duration(now.timeIntervalSince(dl))) overdue" : "Was due \(day(d, now: now).lowercased())"
        }
        if task.hasTime, d <= now { return "Now" }
        if task.hasTime, d > now, d.timeIntervalSince(now) < 3600 {
            return "in \(duration(d.timeIntervalSince(now)))"
        }
        let dayPart = day(d, now: now)
        guard task.hasTime else { return dayPart }
        if cal.isDateInToday(d) || cal.isDateInTomorrow(d) || cal.isDateInYesterday(d) {
            return "\(dayPart) \(time(d))"
        }
        return "\(dayPart), \(time(d))"
    }

    static func day(_ d: Date, now: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: d)).day ?? 0
        if days > 0 && days < 7 { return d.formatted(.dateTime.weekday(.wide)) }
        if cal.isDate(d, equalTo: now, toGranularity: .year) {
            return d.formatted(.dateTime.day().month(.abbreviated))
        }
        return d.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
