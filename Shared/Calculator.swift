import Foundation

/// A small, safe expression evaluator: + − × ÷ ^ %, parentheses, a few functions and constants.
/// Only answers when the text is clearly maths (an operator or a function), so "2024" stays a search.
enum Calculator {
    static func evaluate(_ input: String) -> Double? {
        var text = input.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("=") { text.removeFirst() }
        guard !text.isEmpty, text.count < 200 else { return nil }
        text = text.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "x", with: "*")
            .replacingOccurrences(of: ",", with: "")
        let hasOperator = text.contains(where: { "+-*/^%()".contains($0) })
        let hasFunction = functions.keys.contains { text.contains($0 + "(") } || text.contains("pi")
        guard hasOperator || hasFunction else { return nil }
        // A lone negative number or a leading "+" isn't a question.
        if Double(text) != nil { return nil }
        var parser = Parser(Array(text.filter { !$0.isWhitespace }))
        guard let value = parser.expression(), parser.atEnd, value.isFinite else { return nil }
        return value
    }

    static func format(_ value: Double) -> String {
        if abs(value) >= 1e15 || (abs(value) < 1e-6 && value != 0) { return String(format: "%.6g", value) }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 10
        f.usesGroupingSeparator = true
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    fileprivate static let functions: [String: (Double) -> Double] = [
        "sqrt": { $0.squareRoot() }, "abs": { Swift.abs($0) }, "round": { $0.rounded() },
        "floor": { Foundation.floor($0) }, "ceil": { Foundation.ceil($0) },
        "sin": { Foundation.sin($0 * .pi / 180) }, "cos": { Foundation.cos($0 * .pi / 180) },
        "tan": { Foundation.tan($0 * .pi / 180) }, "ln": { Foundation.log($0) }, "log": { Foundation.log10($0) },
    ]

    private struct Parser {
        let c: [Character]
        var i = 0
        init(_ c: [Character]) { self.c = c }
        var atEnd: Bool { i == c.count }

        mutating func peek() -> Character? { i < c.count ? c[i] : nil }
        mutating func eat(_ ch: Character) -> Bool { if peek() == ch { i += 1; return true }; return false }

        mutating func expression() -> Double? {
            guard var v = term() else { return nil }
            while let ch = peek(), ch == "+" || ch == "-" {
                i += 1
                guard let r = term() else { return nil }
                v = ch == "+" ? v + r : v - r
            }
            return v
        }

        mutating func term() -> Double? {
            guard var v = power() else { return nil }
            while let ch = peek(), ch == "*" || ch == "/" || ch == "%" {
                i += 1
                if ch == "%" {
                    // "20%" is a percentage; "20 % 3" (followed by a number) is a remainder.
                    if let n = peek(), n.isNumber || n == "(" {
                        guard let r = power(), r != 0 else { return nil }
                        v = v.truncatingRemainder(dividingBy: r)
                    } else {
                        v /= 100
                    }
                    continue
                }
                guard let r = power() else { return nil }
                if ch == "/" { guard r != 0 else { return nil }; v /= r } else { v *= r }
            }
            return v
        }

        mutating func power() -> Double? {
            guard let base = unary() else { return nil }
            if eat("^") { guard let e = power() else { return nil }; return Foundation.pow(base, e) }
            return base
        }

        mutating func unary() -> Double? {
            if eat("-") { return unary().map { -$0 } }
            if eat("+") { return unary() }
            return primary()
        }

        mutating func primary() -> Double? {
            if eat("(") {
                guard let v = expression(), eat(")") else { return nil }
                return v
            }
            if let ch = peek(), ch.isLetter {
                var name = ""
                while let l = peek(), l.isLetter { name.append(l); i += 1 }
                if name == "pi" { return .pi }
                if name == "e" { return M_E }
                guard let f = Calculator.functions[name], eat("("), let v = expression(), eat(")") else { return nil }
                return f(v)
            }
            var s = ""
            while let ch = peek(), ch.isNumber || ch == "." { s.append(ch); i += 1 }
            return Double(s)
        }
    }
}
