import Foundation

/// Understands free text like:
///   "Call Anna tomorrow 3pm"              → "Call Anna", tomorrow 15:00
///   "every workday 8:30am Daily"          → "Daily", 8:30 on Mon–Fri
///   "Sleeping time every day 10pm"        → "Sleeping time", daily 22:00
///   "Gym every Mon and Thu 6pm"           → "Gym", Mon & Thu 18:00
///   "Zahnarzt morgen um 10 Uhr"           → "Zahnarzt", tomorrow 10:00
/// Dates come from the system's date detector, so many languages work.
enum QuickParser {
    struct Result: Equatable {
        var title: String
        var date: Date?
        var hasTime: Bool
        var recurrence: Recurrence?
    }

    // MARK: Patterns

    private static func re(_ p: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: [.caseInsensitive])
    }

    private static let dayNames: [(pattern: String, weekday: Int)] = [
        ("mon(day)?s?|montags?", 2), ("tue(s|sday)?s?|dienstags?", 3), ("wed(nesday)?s?|mittwochs?", 4),
        ("thu(r|rs|rsday)?s?|donnerstags?", 5), ("fri(day)?s?|freitags?", 6), ("sat(urday)?s?|samstags?", 7),
        ("sun(day)?s?|sonntags?", 1),
    ]
    private static var anyDay: String { dayNames.map { "(?:\($0.pattern))" }.joined(separator: "|") }

    /// "every …" phrases (and German equivalents) — these always mean repetition.
    private static var explicitRules: [(NSRegularExpression, (NSTextCheckingResult, NSString) -> Recurrence?)] {
        [
            (re(#"\b(every|each)\s+(work\s?day|week\s?day|business\s+day)s?\b|\b(on\s+)?weekdays\b|\b(jeden\s+werktag|werktags|an\s+werktagen)\b"#),
             { _, _ in .everyWorkday }),
            (re(#"\b(every|each)\s+weekend\b|\bon\s+weekends\b|\b(jedes\s+wochenende|am\s+wochenende)\b"#),
             { _, _ in .weekends }),
            (re(#"\b(every|each)\s+(day|night|morning|evening)\b|\b(jeden\s+(tag|morgen|abend)|jede\s+nacht)\b"#),
             { _, _ in .daily }),
            (re(#"\bevery\s+other\s+(day|week|month|year)\b"#),
             { m, ns in Recurrence(unit: unit(ns.substring(with: m.range(at: 1))), interval: 2) }),
            (re(#"\b(?:every|alle)\s+(\d{1,3})\s+(days?|weeks?|months?|years?|tage|wochen|monate|jahre)\b"#),
             { m, ns in Recurrence(unit: unit(ns.substring(with: m.range(at: 2))), interval: Int(ns.substring(with: m.range(at: 1))) ?? 1) }),
            (re(#"\b(every|each)\s+week\b|\bjede\s+woche\b"#), { _, _ in .weekly }),
            (re(#"\b(every|each)\s+month\b|\bjeden\s+monat\b"#), { _, _ in .monthly }),
            (re(#"\b(every|each)\s+year\b|\bjedes\s+jahr\b"#), { _, _ in .yearly }),
            (re(#"\b(?:every|each|jeden)\s+((?:"# + anyDay + #")(?:\s*(?:,|and|&|und|\+)\s*(?:"# + anyDay + #"))*)\b"#),
             { m, ns in weekdays(in: ns.substring(with: m.range(at: 1))) }),
        ]
    }

    /// Bare adverbs like "daily" — only used when they aren't the first word,
    /// so a task simply called "Daily" or "Weekly sync" keeps its name.
    private static let adverbRules: [(NSRegularExpression, Recurrence)] = [
        (re(#"\b(daily|nightly|täglich)\b"#), .daily),
        (re(#"\b(weekly|wöchentlich)\b"#), .weekly),
        (re(#"\b(monthly|monatlich)\b"#), .monthly),
        (re(#"\b(yearly|annually|jährlich)\b"#), .yearly),
    ]

    private static let relative = re(#"\bin\s+(?:about\s+)?(\d{1,3})\s*(m|min|mins|minute|minutes|minuten|h|hr|hrs|hour|hours|stunde|stunden)\b"#)

    private static let timeHint = re(#"(\d{1,2}[:.]\d{2})|(\b\d{1,2}\s*(am|pm|a\.m\.|p\.m\.|uhr|h)\b)|\b(noon|midnight|morning|afternoon|evening|tonight|mittag|abend|morgens|früh)\b"#)

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    private static let danglingWords: Set<String> = ["at", "on", "by", "due", "until", "am", "um", "bis", "ab", "for", "from", "and", "&"]

    // MARK: Parse

    static func parse(_ text: String, now: Date = Date()) -> Result? {
        var working = text
        var recurrence: Recurrence?

        // 1. Repetition
        let ns0 = working as NSString
        for (regex, build) in explicitRules {
            if let m = regex.firstMatch(in: working, range: NSRange(location: 0, length: ns0.length)),
               let r = build(m, ns0) {
                recurrence = r
                working = ns0.replacingCharacters(in: m.range, with: " ")
                break
            }
        }
        if recurrence == nil {
            let ns = working as NSString
            for (regex, rule) in adverbRules {
                if let m = regex.firstMatch(in: working, range: NSRange(location: 0, length: ns.length)),
                   !isFirstWord(m.range, in: working) {
                    recurrence = rule
                    working = ns.replacingCharacters(in: m.range, with: " ")
                    break
                }
            }
        }

        // 2. Date & time
        var date: Date?
        var hasTime = false
        let ns = working as NSString
        let full = NSRange(location: 0, length: ns.length)
        if let m = relative.firstMatch(in: working, range: full),
           let amount = Double(ns.substring(with: m.range(at: 1))) {
            let unitText = ns.substring(with: m.range(at: 2)).lowercased()
            date = now.addingTimeInterval(unitText.hasPrefix("m") ? amount * 60 : amount * 3600)
            hasTime = true
            working = ns.replacingCharacters(in: m.range, with: " ")
        } else if let detector, let m = detector.matches(in: working, range: full).last, var d = m.date {
            let matched = ns.substring(with: m.range)
            hasTime = timeHint.firstMatch(in: matched, range: NSRange(location: 0, length: (matched as NSString).length)) != nil
            if !hasTime {
                d = Calendar.current.startOfDay(for: d)
            } else if d < now.addingTimeInterval(-60), Calendar.current.isDateInToday(d),
                      !matched.lowercased().contains("today"), recurrence == nil {
                // "at 9" when it's already 14:00 means tomorrow at 9.
                d = Calendar.current.date(byAdding: .day, value: 1, to: d) ?? d
            }
            date = d
            working = ns.replacingCharacters(in: m.range, with: " ")
        }

        guard date != nil || recurrence != nil else { return nil }

        // 3. Repeating tasks start on the first matching occurrence that's still ahead.
        if let r = recurrence {
            var d = date ?? Calendar.current.startOfDay(for: now)
            d = r.aligned(d)
            if hasTime, d < now { d = r.next(after: d, now: now) }
            date = d
        }

        let title = clean(working)
        guard !title.isEmpty else { return nil }
        return Result(title: title, date: date, hasTime: hasTime, recurrence: recurrence)
    }

    // MARK: Helpers

    private static func unit(_ s: String) -> Recurrence.Unit {
        let l = s.lowercased()
        if l.hasPrefix("w") { return .week }
        if l.hasPrefix("m") { return .month }
        if l.hasPrefix("y") || l.hasPrefix("j") { return .year }
        return .day
    }

    private static func weekdays(in s: String) -> Recurrence? {
        var set = Set<Int>()
        let ns = s as NSString
        for (pattern, weekday) in dayNames {
            if re(#"\b(?:"# + pattern + #")\b"#).firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) != nil {
                set.insert(weekday)
            }
        }
        return set.isEmpty ? nil : Recurrence(unit: .week, weekdays: set)
    }

    private static func isFirstWord(_ range: NSRange, in text: String) -> Bool {
        let prefix = (text as NSString).substring(to: range.location)
        return prefix.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func clean(_ s: String) -> String {
        var words = s.split(whereSeparator: \.isWhitespace).map(String.init)
        while let last = words.last, danglingWords.contains(last.lowercased()) { words.removeLast() }
        while let first = words.first, danglingWords.contains(first.lowercased()) { words.removeFirst() }
        var out = words.joined(separator: " ")
        while let last = out.last, ",;-–".contains(last) { out.removeLast() }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
