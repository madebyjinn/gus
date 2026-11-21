import Foundation
import FoundationModels

/// For phrasing the instant parsers don't know ("how many seconds in a week", "what's 3 dozen eggs minus
/// 7", "days until christmas", "time in tokyo", "20 bucks in rupees"), the on-device model only
/// *translates* the words into a calculation, conversion, date or place. Gus then works the answer out
/// itself, so the model never does the arithmetic and nothing leaves the Mac.
@Generable
struct LocalIntent {
    @Guide(description: "One of: math, unit, currency, days_until, date_offset, time_in, none")
    var kind: String
    @Guide(description: "For math: one arithmetic expression using only digits, + - * / ^ ( ) and %. Empty otherwise.")
    var expression: String
    @Guide(description: "For unit or currency: the amount as a number. 0 otherwise.")
    var amount: Double
    @Guide(description: "For unit: the source unit as a short symbol like km, mi, kg, lb, c, f, ml, cups, hours, gb. For currency: a 3-letter ISO code. Empty otherwise.")
    var from: String
    @Guide(description: "For unit: the target unit symbol. For currency: a 3-letter ISO code, or empty for the user's own currency.")
    var to: String
    @Guide(description: "For days_until: the target date as yyyy-MM-dd (the next one, from today). Empty otherwise.")
    var date: String
    @Guide(description: "For date_offset: days from today, negative for the past. 0 otherwise.")
    var days: Int
    @Guide(description: "For time_in: the IANA time zone identifier of the place, like Asia/Tokyo. Empty otherwise.")
    var timeZone: String
}

struct LocalAnswer { let title: String; let subtitle: String; let copy: String }

@MainActor
enum LocalAnswers {
    private static let numberWords: Set<String> = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
        "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen",
        "nineteen", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety", "hundred",
        "thousand", "million", "billion", "dozen", "half", "quarter", "double", "triple", "a", "an"]
    private static let timeWords: Set<String> = ["second", "seconds", "minute", "minutes", "hour", "hours", "day", "days",
        "week", "weeks", "month", "months", "year", "years", "decade", "century"]
    private static let filler: Set<String> = ["what", "is", "whats", "what's", "how", "much", "many", "the", "of", "in", "a",
        "an", "to", "calculate", "convert", "tell", "me", "please", "are", "there", "does", "do", "it", "be", "will"]

    private static func words(_ q: String) -> [String] {
        q.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
    }

    /// Worth asking the model? Only a finished-looking request with something to work on: a number, a number
    /// word, a time span, or a date or place question. "what is" alone is not.
    static func worthAsking(_ q: String) -> Bool {
        guard q.count >= 8, q.count <= 140 else { return false }
        let w = words(q)
        let content = w.filter { !filler.contains($0) }
        guard content.count >= 2 || (content.count == 1 && q.contains(where: \.isNumber)) else { return false }
        let l = q.lowercased()
        let hasNumber = q.contains(where: \.isNumber) || w.contains { numberWords.contains($0) && $0 != "a" && $0 != "an" }
        let dateOrPlace = ["until", "till", "from now", "ago", "time in", "time is it in", "days to"].contains { l.contains($0) }
        return hasNumber || dateOrPlace || w.filter { timeWords.contains($0) }.count >= 2
    }

    /// The model only translates; this checks the translation is about what was typed, so a half-typed
    /// "what is" can never come back as "€910.75".
    static func grounded(_ i: LocalIntent, in q: String) -> Bool {
        let w = Set(words(q))
        let l = q.lowercased()
        func mentioned(_ amount: Double) -> Bool {
            let n = amount == amount.rounded() ? String(Int(amount)) : String(amount)
            if l.replacingOccurrences(of: ",", with: "").contains(n) { return true }
            // A number said in words: accept if any number word is there and the expression has no
            // other digits to explain.
            return w.contains { numberWords.contains($0) && $0 != "a" && $0 != "an" }
        }
        switch i.kind {
        case "math":
            let digits = i.expression.split(whereSeparator: { !$0.isNumber && $0 != "." }).compactMap { Double($0) }
            guard !digits.isEmpty else { return false }
            // Every number in the sum comes from the text, or the text is about time spans (7*24*60*60).
            let spans = w.filter { timeWords.contains($0) }.count >= 2
            return spans || digits.allSatisfy { mentioned($0) }
        case "unit", "currency":
            return i.amount != 0 && mentioned(i.amount)
        case "days_until":
            return ["until", "till", "to", "before"].contains { w.contains($0) } && !i.date.isEmpty
        case "date_offset":
            return (l.contains("from now") || l.contains("ago") || l.contains("later") || l.contains("from today")) && mentioned(Double(abs(i.days)))
        case "time_in":
            let place = (i.timeZone.split(separator: "/").last.map(String.init) ?? "").lowercased().replacingOccurrences(of: "_", with: " ")
            return l.contains("time") && !place.isEmpty && (l.contains(place) || place.split(separator: " ").contains { l.contains($0) })
        default:
            return false
        }
    }

    static func interpret(_ q: String) async -> LocalAnswer? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let today = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        let session = LanguageModelSession(instructions: """
            You translate a short request typed into a Mac search bar into structured data. Today is \(today). \
            Never compute the answer yourself; only fill the fields. Use only numbers that appear in the request. \
            If the request is unfinished, vague, or isn't maths, a unit or currency conversion, a date question or \
            a time-in-a-place question, use kind none.
            """)
        guard let intent = try? await session.respond(to: q, generating: LocalIntent.self, includeSchemaInPrompt: true).content,
              grounded(intent, in: q) else { return nil }
        return compute(intent, original: q)
    }

    static func compute(_ i: LocalIntent, original: String) -> LocalAnswer? {
        switch i.kind {
        case "math":
            guard let v = Calculator.evaluate(i.expression) ?? Calculator.evaluate("(" + i.expression + ")+0") else { return nil }
            let shown = Calculator.format(v)
            return LocalAnswer(title: shown, subtitle: "\(i.expression) · worked out on this Mac",
                               copy: shown.replacingOccurrences(of: ",", with: ""))
        case "unit":
            guard i.amount != 0, let r = Units.convert(i.amount, i.from, i.to) else { return nil }
            let d = Units.describe(r)
            return LocalAnswer(title: d.title, subtitle: d.subtitle, copy: d.plain)
        case "currency":
            let from = i.from.uppercased()
            let to = i.to.isEmpty ? Currency.local : i.to.uppercased()
            guard i.amount != 0, let v = Rates.shared.convert(i.amount, from: from, to: to) else { return nil }
            let shown = Currency.format(v, to)
            return LocalAnswer(title: shown, subtitle: "\(Currency.format(i.amount, from)) in \(to)", copy: String(format: "%.2f", v))
        case "days_until":
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
            guard let target = f.date(from: i.date) else { return nil }
            let cal = Calendar.current
            let n = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: target)).day ?? 0
            let when = target.formatted(date: .complete, time: .omitted)
            return LocalAnswer(title: n == 1 ? "1 day" : "\(n) days", subtitle: "Until \(when)", copy: String(n))
        case "date_offset":
            guard let d = Calendar.current.date(byAdding: .day, value: i.days, to: Date()) else { return nil }
            let shown = d.formatted(date: .complete, time: .omitted)
            let sub = i.days >= 0 ? "\(i.days) days from today" : "\(-i.days) days ago"
            return LocalAnswer(title: shown, subtitle: sub, copy: shown)
        case "time_in":
            guard let tz = TimeZone(identifier: i.timeZone) else { return nil }
            let f = DateFormatter(); f.timeZone = tz; f.dateFormat = "h:mm a"
            let day = DateFormatter(); day.timeZone = tz; day.dateFormat = "EEEE d MMM"
            let diff = (tz.secondsFromGMT() - TimeZone.current.secondsFromGMT()) / 60
            let rel = diff == 0 ? "same time as here" : "\(diff > 0 ? "+" : "−")\(abs(diff) / 60)h\(abs(diff) % 60 == 0 ? "" : " \(abs(diff) % 60)m") from here"
            let place = tz.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? tz.identifier
            return LocalAnswer(title: f.string(from: Date()), subtitle: "\(place) · \(day.string(from: Date())) · \(rel)",
                               copy: f.string(from: Date()))
        default:
            return nil
        }
    }
}
