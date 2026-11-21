import Foundation

/// Turns "remind me to call mum tomorrow at 5" into a title and a time. Pure text work, so it can be
/// tested without Reminders.
enum ReminderParser {
    struct Draft: Equatable { var title: String; var due: Date? }

    static let prefixes = ["remind me to ", "remind me ", "reminder to ", "reminder ", "remind ", "todo ", "to do "]

    static func draft(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> Draft? {
        let lower = text.lowercased()
        guard let p = prefixes.first(where: { lower.hasPrefix($0) }) else { return nil }
        var body = String(text.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
        // "remind me", "remind me to": nothing to be reminded of yet.
        guard !body.isEmpty, !["me", "me to", "to"].contains(body.lowercased()) else { return nil }
        var due: Date?

        // "in 20 minutes", "in 2 hours", "in 3 days": the date detector doesn't know these.
        if let m = body.range(of: #"\bin (\d+|an?|half an) ?(min(ute)?s?|h(ou)?rs?|days?|weeks?)\b"#, options: [.regularExpression, .caseInsensitive]) {
            let phrase = body[m].lowercased()
            let parts = phrase.dropFirst(3).split(separator: " ")
            var amount = Double(parts.first.map(String.init) ?? "") ?? 1
            let unit = String(parts.last ?? "")
            if phrase.contains("half an") { amount = 0.5 }
            let seconds: Double = unit.hasPrefix("min") ? 60 : unit.hasPrefix("h") ? 3600 : unit.hasPrefix("day") ? 86400 : 604800
            due = now.addingTimeInterval(amount * seconds)
            body.removeSubrange(m)
        } else if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
                  let match = detector.matches(in: body, range: NSRange(body.startIndex..., in: body)).last,
                  let range = Range(match.range, in: body), var date = match.date {
            // A bare clock time that has already gone today ("at 9.30" typed at noon) means the next one.
            let phrase = body[range].lowercased()
            let namesDay = ["today", "tonight", "tomorrow", "mon", "tue", "wed", "thu", "fri", "sat", "sun", "/", "jan", "feb", "mar",
                            "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec", "next", "morning", "evening", "noon"]
                .contains { phrase.contains($0) }
            let saysHalf = phrase.contains("am") || phrase.contains("pm")
            if date < now, !namesDay {
                if !saysHalf, date.addingTimeInterval(12 * 3600) > now { date = date.addingTimeInterval(12 * 3600) }
                else { date = calendar.date(byAdding: .day, value: 1, to: date) ?? date }
            }
            due = date
            body.removeSubrange(range)
        } else if let m = body.range(of: #"\bat (\d{1,2})\s*$"#, options: .regularExpression) {
            // "at 9": the next time the clock shows 9.
            let hour = Int(body[m].dropFirst(3).trimmingCharacters(in: .whitespaces)) ?? 0
            if (1...23).contains(hour) {
                let candidates = (hour <= 12 ? [hour % 12, hour % 12 + 12] : [hour]).compactMap {
                    calendar.nextDate(after: now, matching: DateComponents(hour: $0, minute: 0), matchingPolicy: .nextTime)
                }
                due = candidates.min()
                body.removeSubrange(m)
            }
        }
        body = body.trimmingCharacters(in: .whitespaces)
        var trimmed = true
        while trimmed {
            trimmed = false
            for tail in [" at", " on", " by", " in", " for"] where body.lowercased().hasSuffix(tail) {
                body = String(body.dropLast(tail.count)); trimmed = true
            }
        }
        body = body.replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !body.isEmpty else { return nil }
        return Draft(title: body.prefix(1).uppercased() + body.dropFirst(), due: due)
    }
}

/// "Today 9:30 PM", "Tomorrow 5:00 PM", "Fri 27 Nov, 12:00 PM".
enum ReminderWhen {
    static func text(_ date: Date, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Today \(time)" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow \(time)" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + ", " + time
    }
}
