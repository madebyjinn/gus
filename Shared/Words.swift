import Foundation

/// Plain-English maths, turned into something the calculator reads: "what is ten times 12" → "10*12",
/// "fifteen percent of 80" → "15%*80", "half of 37" → "37/2". Deterministic and instant; Apple
/// Intelligence only steps in for phrasing this doesn't know.
enum NumberWords {
    private static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90, "a": 1, "an": 1, "dozen": 12,
    ]
    private static let scales: [String: Double] = ["hundred": 100, "thousand": 1_000, "million": 1_000_000,
                                                   "billion": 1_000_000_000, "k": 1_000]

    /// Returns a calculator expression, or nil when the text isn't recognisably maths.
    static func expression(_ input: String) -> String? {
        var text = input.lowercased()
            .replacingOccurrences(of: "?", with: " ").replacingOccurrences(of: ",", with: " ")
        // "twenty-five" is one number; a real minus sign is left alone.
        text = text.replacingOccurrences(of: #"(?<=[a-z])-(?=[a-z])"#, with: " ", options: .regularExpression)
        for filler in ["what is", "what's", "whats", "how much is", "calculate", "compute", "tell me", "equals", "please", "="] {
            text = text.replacingOccurrences(of: filler, with: " ")
        }
        // Phrases first, longest first, so "divided by" wins over "by".
        let phrases: [(String, String)] = [
            ("multiplied by", " * "), ("divided by", " / "), ("to the power of", " ^ "), ("raised to", " ^ "),
            ("percent of", " % * "), ("% of", " % * "), ("square root of", " sqrt "), ("squared", " ^ 2 "),
            ("cubed", " ^ 3 "), ("half of", " 0.5 * "), ("a third of", " (1/3) * "), ("a quarter of", " 0.25 * "),
            ("double", " 2 * "), ("triple", " 3 * "), ("times", " * "), ("plus", " + "), ("minus", " - "),
            ("less", " - "), ("over", " / "), ("into", " * "), ("x", " * "), ("and", " "), ("percent", " % "),
        ]
        for (p, r) in phrases {
            text = text.replacingOccurrences(of: "\\b" + NSRegularExpression.escapedPattern(for: p) + "\\b", with: r,
                                             options: .regularExpression)
        }
        // Number words → digits ("twenty five thousand" → 25000).
        var out: [String] = []
        var current: Double? = nil
        var total: Double = 0
        func flush() {
            if let c = current { out.append(trim(total + c)) } else if total > 0 { out.append(trim(total)) }
            current = nil; total = 0
        }
        var sawWordNumber = false
        for token in text.split(separator: " ").map(String.init) {
            if let u = units[token], !(token == "a" || token == "an") || current == nil {
                current = (current ?? 0) + Double(u); sawWordNumber = true
            } else if let s = scales[token], current != nil || token == "k" {
                let c = current ?? 1
                if s >= 1000 { total += c * s; current = nil } else { current = c * s }
                sawWordNumber = true
            } else {
                flush()
                out.append(token)
            }
        }
        flush()
        let expr = out.joined(separator: " ")
            .replacingOccurrences(of: #"sqrt\s+([0-9.]+)"#, with: "sqrt($1)", options: .regularExpression)
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/^%() ").union(.whitespaces)
        let stripped = expr.replacingOccurrences(of: "sqrt", with: "")
        guard stripped.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        guard sawWordNumber || input.rangeOfCharacter(from: .letters) != nil else { return nil }
        guard Calculator.evaluate(expr) != nil else { return nil }
        return expr
    }

    private static func trim(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }
}

/// "5 km in miles", "72 f to c", "3 cups to ml": Foundation's Measurement does the conversion.
enum Units {
    private static let table: [String: Dimension] = [
        "mm": UnitLength.millimeters, "cm": UnitLength.centimeters, "m": UnitLength.meters, "meter": UnitLength.meters,
        "meters": UnitLength.meters, "metre": UnitLength.meters, "metres": UnitLength.meters,
        "km": UnitLength.kilometers, "kilometer": UnitLength.kilometers, "kilometers": UnitLength.kilometers,
        "kilometre": UnitLength.kilometers, "kilometres": UnitLength.kilometers,
        "in": UnitLength.inches, "inch": UnitLength.inches, "inches": UnitLength.inches, "ft": UnitLength.feet,
        "foot": UnitLength.feet, "feet": UnitLength.feet, "yd": UnitLength.yards, "yard": UnitLength.yards,
        "yards": UnitLength.yards, "mi": UnitLength.miles, "mile": UnitLength.miles, "miles": UnitLength.miles,
        "g": UnitMass.grams, "gram": UnitMass.grams, "grams": UnitMass.grams, "kg": UnitMass.kilograms,
        "kilo": UnitMass.kilograms, "kilos": UnitMass.kilograms, "kilogram": UnitMass.kilograms,
        "kilograms": UnitMass.kilograms, "lb": UnitMass.pounds, "lbs": UnitMass.pounds, "pound": UnitMass.pounds,
        "oz": UnitMass.ounces, "ounce": UnitMass.ounces, "ounces": UnitMass.ounces, "stone": UnitMass.stones,
        "ml": UnitVolume.milliliters, "l": UnitVolume.liters, "liter": UnitVolume.liters, "liters": UnitVolume.liters,
        "litre": UnitVolume.liters, "litres": UnitVolume.liters, "cup": UnitVolume.cups, "cups": UnitVolume.cups,
        "tsp": UnitVolume.teaspoons, "tbsp": UnitVolume.tablespoons, "gal": UnitVolume.gallons,
        "gallon": UnitVolume.gallons, "gallons": UnitVolume.gallons, "floz": UnitVolume.fluidOunces,
        "c": UnitTemperature.celsius, "celsius": UnitTemperature.celsius, "f": UnitTemperature.fahrenheit,
        "fahrenheit": UnitTemperature.fahrenheit, "k": UnitTemperature.kelvin, "kelvin": UnitTemperature.kelvin,
        "kmh": UnitSpeed.kilometersPerHour, "kph": UnitSpeed.kilometersPerHour, "mph": UnitSpeed.milesPerHour,
        "kb": UnitInformationStorage.kilobytes, "mb": UnitInformationStorage.megabytes,
        "gb": UnitInformationStorage.gigabytes, "tb": UnitInformationStorage.terabytes,
        "hour": UnitDuration.hours, "hours": UnitDuration.hours, "minute": UnitDuration.minutes,
        "minutes": UnitDuration.minutes, "min": UnitDuration.minutes, "second": UnitDuration.seconds,
        "seconds": UnitDuration.seconds, "sec": UnitDuration.seconds,
        "acre": UnitArea.acres, "acres": UnitArea.acres, "hectare": UnitArea.hectares, "hectares": UnitArea.hectares,
    ]

    static func unit(_ name: String) -> Dimension? {
        table[name.lowercased().replacingOccurrences(of: "°", with: "").replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: ".", with: "")]
    }

    struct Result { let value: Double; let from: Dimension; let to: Dimension; let amount: Double }

    static func parse(_ input: String) -> Result? {
        let text = input.lowercased().replacingOccurrences(of: "?", with: "").trimmingCharacters(in: .whitespaces)
        let re = try! NSRegularExpression(pattern: #"^(?:convert\s+|how many\s+)?([0-9][0-9.,]*)\s*°?\s*([a-z/.]+)\s+(?:to|in|into|as)\s+°?([a-z/.]+)$"#)
        guard let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let a = Range(m.range(at: 1), in: text), let f = Range(m.range(at: 2), in: text), let t = Range(m.range(at: 3), in: text),
              let amount = Double(text[a].replacingOccurrences(of: ",", with: "")) else { return nil }
        return convert(amount, String(text[f]), String(text[t]))
    }

    static func convert(_ amount: Double, _ fromName: String, _ toName: String) -> Result? {
        guard let from = unit(fromName), let to = unit(toName), type(of: from) == type(of: to) else { return nil }
        let value = Measurement(value: amount, unit: from).converted(to: to).value
        return Result(value: value, from: from, to: to, amount: amount)
    }

    static func describe(_ r: Result) -> (title: String, subtitle: String, plain: String) {
        let f = MeasurementFormatter()
        f.unitOptions = .providedUnit
        f.unitStyle = .medium
        f.numberFormatter.maximumFractionDigits = r.value.magnitude >= 100 ? 1 : 3
        let title = f.string(from: Measurement(value: r.value, unit: r.to))
        let sub = f.string(from: Measurement(value: r.amount, unit: r.from))
        return (title, "\(sub) in \(r.to.symbol)", Calculator.format(r.value).replacingOccurrences(of: ",", with: ""))
    }
}
