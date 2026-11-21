import Foundation

/// "$5", "5 usd", "€20 in inr", "10k yen to gbp" → the amount in your currency (or the one asked for).
/// Rates come from open.er-api.com (no key, no account), cached on disk and refreshed every 6 hours.
enum Currency {
    struct Query: Equatable { var amount: Double; var from: String; var to: String? }

    static let symbols: [String: String] = ["$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₹": "INR", "₩": "KRW",
                                            "₽": "RUB", "₺": "TRY", "₫": "VND", "₱": "PHP", "฿": "THB", "₪": "ILS"]
    static let names: [String: String] = [
        "dollar": "USD", "dollars": "USD", "bucks": "USD", "euro": "EUR", "euros": "EUR", "pound": "GBP",
        "pounds": "GBP", "quid": "GBP", "yen": "JPY", "rupee": "INR", "rupees": "INR", "rs": "INR",
        "dirham": "AED", "dirhams": "AED", "yuan": "CNY", "rmb": "CNY", "franc": "CHF", "francs": "CHF",
        "won": "KRW", "baht": "THB", "ringgit": "MYR", "peso": "MXN", "pesos": "MXN", "real": "BRL",
    ]

    /// Codes the rate source knows; filled from the cached table so "usd"/"eur" match but "cat" doesn't.
    nonisolated(unsafe) static var known: Set<String> = ["USD", "EUR", "GBP", "JPY", "INR", "AUD", "CAD", "CHF", "CNY", "AED",
                                                         "SGD", "HKD", "NZD", "SEK", "NOK", "DKK", "KRW", "MXN", "BRL", "ZAR",
                                                         "THB", "MYR", "IDR", "PHP", "SAR", "TRY", "RUB", "PLN", "ILS", "VND"]

    private static func code(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if let s = symbols[t] { return s }
        if let n = names[t.lowercased()] { return n }
        let u = t.uppercased()
        return u.count == 3 && known.contains(u) ? u : nil
    }

    static func parse(_ input: String) -> Query? {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard text.count <= 40 else { return nil }
        let unit = #"([$€£¥₹₩₽₺₫₱฿₪]|[A-Za-z]{2,8})"#
        let pattern = "^" + unit + #"?\s*([0-9][0-9.,]*)\s*([kKmM])?\s*"# + unit + #"?(?:\s+(?:to|in|as|=)\s+"# + unit + #")?$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ i: Int) -> String? {
            guard let r = Range(m.range(at: i), in: text) else { return nil }
            return String(text[r])
        }
        guard var amount = group(2).flatMap({ Double($0.replacingOccurrences(of: ",", with: "")) }) else { return nil }
        if let mult = group(3)?.lowercased() { amount *= mult == "k" ? 1_000 : 1_000_000 }
        let before = group(1).flatMap(code)
        let after = group(4).flatMap(code)
        // A word before the number that isn't a currency ("page 5") means this isn't money.
        if group(1) != nil && before == nil { return nil }
        if group(4) != nil && after == nil { return nil }
        guard let from = before ?? after else { return nil }
        let to = group(5).flatMap(code)
        if group(5) != nil && to == nil { return nil }
        return Query(amount: amount, from: from, to: to)
    }

    /// Your currency: the one you set in Gus, else your region's, else a guess from the time zone.
    static var local: String {
        if let c = Region.locale.currency?.identifier { return c }
        let tz = TimeZone.current.identifier
        let byZone = ["Asia/Kolkata": "INR", "Asia/Calcutta": "INR", "Europe/London": "GBP", "Asia/Tokyo": "JPY",
                      "Asia/Dubai": "AED", "Asia/Singapore": "SGD", "Australia/Sydney": "AUD"]
        return byZone[tz] ?? (tz.hasPrefix("Europe/") ? "EUR" : "USD")
    }

    static func format(_ value: Double, _ code: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        f.maximumFractionDigits = value >= 100 ? 2 : (value >= 1 ? 2 : 4)
        return f.string(from: NSNumber(value: value)) ?? "\(value) \(code)"
    }
}

/// The rate table: rates relative to USD.
@MainActor
final class Rates: ObservableObject {
    static let shared = Rates()
    @Published private(set) var table: [String: Double] = [:]
    @Published private(set) var updated: Date?
    private var loading = false

    private var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Gus")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("rates.json")
    }

    private struct Saved: Codable { var rates: [String: Double]; var updated: Date }

    private init() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            table = saved.rates
            updated = saved.updated
            Currency.known.formUnion(saved.rates.keys)
        }
    }

    func refreshIfStale() {
        if let updated, Date().timeIntervalSince(updated) < 6 * 3600 { return }
        guard !loading else { return }
        loading = true
        Task {
            defer { loading = false }
            guard let url = URL(string: "https://open.er-api.com/v6/latest/USD") else { return }
            let data: Data
            do { data = try await URLSession.shared.data(from: url).0 } catch { NSLog("Gus rates: %@", "\(error)"); return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rates = json["rates"] as? [String: Double], !rates.isEmpty else { NSLog("Gus rates: bad reply"); return }
            table = rates
            updated = Date()
            Currency.known.formUnion(rates.keys)
            if let data = try? JSONEncoder().encode(Saved(rates: rates, updated: updated!)) { try? data.write(to: file) }
        }
    }

    func convert(_ amount: Double, from: String, to: String) -> Double? {
        if from == to { return amount }
        guard let f = table[from], let t = table[to], f > 0 else { return nil }
        return amount / f * t
    }
}

/// The region Gus assumes: the Mac's, unless one is picked in Settings. It decides the currency amounts
/// convert to and whether weather comes in °C or °F.
enum Region {
    static var code: String { UserDefaults.standard.string(forKey: "region") ?? "" }
    static var locale: Locale {
        let c = code
        return c.isEmpty ? Locale.current : Locale(identifier: "\(Locale.current.language.languageCode?.identifier ?? "en")_\(c)")
    }
    static func name(_ code: String) -> String { Locale.current.localizedString(forRegionCode: code) ?? code }
    /// Countries that have a currency, by name.
    static let all: [String] = Locale.Region.isoRegions
        .filter { $0.subRegions.isEmpty && $0.identifier.count == 2 && Locale(identifier: "en_\($0.identifier)").currency != nil }
        .map(\.identifier).sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
}
