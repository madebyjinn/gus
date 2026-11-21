import AppKit
import CoreLocation
import CoreServices
import IOKit.ps

/// Everyday questions Gus answers itself, mostly without the network:
/// - date, day and time ("what day is it", "today's date", "what time is it")
/// - battery ("battery", "how much charge") and storage ("disk space", "storage left")
/// - definitions from the Mac's own dictionary ("define serendipity", "meaning of ennui")
/// - weather, sunrise and sunset for where you are or a named place (Open-Meteo: free, no account;
///   your location comes from Location Services and is only sent as rounded coordinates)
@MainActor
enum General {
    // MARK: Instant

    static func instant(_ q: String) -> [Hit] {
        let l = q.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " ?.!"))
        func has(_ any: String...) -> Bool { any.contains { l.contains($0) } }
        func hit(_ id: String, _ symbol: String, _ title: String, _ subtitle: String, copy: String, open: (() -> Void)? = nil) -> Hit {
            Hit(id: id, icon: .symbol(symbol), title: title, subtitle: subtitle, hint: open == nil ? "Copy" : "Open",
                group: .answer, score: 100, big: true,
                run: { if let open { open() } else { Pasteboard.copy(copy); Launcher.shared.say("Copied \(title)") } },
                copyText: copy)
        }

        if ["date", "today", "todays date", "today's date", "whats the date", "what's the date", "what is the date",
            "what date is it", "what day is it", "what day is today", "which day is today", "day today"].contains(l) {
            let d = Date()
            let title = d.formatted(.dateTime.weekday(.wide).day().month(.wide))
            let week = Calendar.current.component(.weekOfYear, from: d)
            let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: d) ?? 0
            return [hit("general:date", "calendar", title, "\(d.formatted(.dateTime.year())) · week \(week) · day \(dayOfYear)",
                        copy: d.formatted(date: .long, time: .omitted))]
        }
        if ["time", "what time is it", "whats the time", "what's the time", "what is the time", "current time", "time now"].contains(l) {
            let d = Date()
            let tz = TimeZone.current
            return [hit("general:time", "clock", d.formatted(date: .omitted, time: .shortened),
                        "\(tz.localizedName(for: .standard, locale: .current) ?? tz.identifier) · \(d.formatted(.dateTime.weekday(.wide)))",
                        copy: d.formatted(date: .omitted, time: .shortened))]
        }
        if has("battery", "charge left", "how much charge", "power left") {
            if let b = battery() {
                let state = b.charging ? "Charging" : (b.plugged ? "Plugged in" : "On battery")
                let left = b.minutes.map { $0 > 0 ? " · \($0 / 60)h \($0 % 60)m \(b.charging ? "to full" : "left")" : "" } ?? ""
                return [hit("general:battery", b.charging ? "battery.100.bolt" : "battery.75", "\(b.percent)%", state + left,
                            copy: "\(b.percent)%")]
            }
            return [hit("general:battery", "powerplug", "No battery", "This Mac runs on mains power", copy: "")]
        }
        if has("disk space", "storage", "free space", "space left", "how much space") {
            let url = URL(fileURLWithPath: "/")
            if let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
               let free = v.volumeAvailableCapacityForImportantUsage, let total = v.volumeTotalCapacity {
                let f = ByteCountFormatter(); f.countStyle = .file
                return [hit("general:storage", "internaldrive", "\(f.string(fromByteCount: free)) free",
                            "of \(f.string(fromByteCount: Int64(total))) on this Mac",
                            copy: f.string(fromByteCount: free))]
            }
        }
        if let word = definitionWord(l), let def = define(word) {
            let first = def.components(separatedBy: CharacterSet.newlines).first ?? def
            return [hit("general:define", "character.book.closed", word, String(first.prefix(160)), copy: def,
                        open: { NSWorkspace.shared.open(URL(string: "dict://\(word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word)")!) })]
        }
        return []
    }

    private static func definitionWord(_ l: String) -> String? {
        for p in ["define ", "definition of ", "meaning of ", "what does ", "what is the meaning of "] where l.hasPrefix(p) {
            var w = String(l.dropFirst(p.count))
            if p == "what does " { guard w.hasSuffix(" mean") else { return nil }; w = String(w.dropLast(5)) }
            w = w.trimmingCharacters(in: .whitespaces)
            return w.isEmpty || w.count > 40 ? nil : w
        }
        return nil
    }

    private static func define(_ word: String) -> String? {
        let range = CFRange(location: 0, length: (word as NSString).length)
        guard let def = DCSCopyTextDefinition(nil, word as CFString, range)?.takeRetainedValue() else { return nil }
        return (def as String).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Battery { let percent: Int; let charging: Bool; let plugged: Bool; let minutes: Int? }
    private static func battery() -> Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  let cap = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            let plugged = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let mins = (charging ? d[kIOPSTimeToFullChargeKey] : d[kIOPSTimeToEmptyKey]) as? Int
            return Battery(percent: cap * 100 / max, charging: charging, plugged: plugged, minutes: (mins ?? -1) > 0 ? mins : nil)
        }
        return nil
    }

    // MARK: Weather

    struct WeatherAsk { var place: String?; var day: Int; var sun: Bool }

    /// "weather", "today's weather", "weather tomorrow", "will it rain", "temperature", "weather in london",
    /// "sunset", "when is sunrise tomorrow".
    static func weatherAsk(_ q: String) -> WeatherAsk? {
        let l = q.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " ?.!"))
        let words = ["weather", "temperature", "forecast", "will it rain", "is it raining", "rain today", "rain tomorrow",
                     "how hot", "how cold", "humidity", "sunrise", "sunset", "umbrella"]
        guard words.contains(where: { l.contains($0) }) else { return nil }
        var place: String?
        if let r = l.range(of: #"\b(?:in|at|for)\s+([a-z .'-]+?)(?:\s+(?:today|tomorrow|now|this week))?$"#, options: .regularExpression) {
            let tail = l[r].replacingOccurrences(of: #"^(in|at|for)\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+(today|tomorrow|now|this week)$"#, with: "", options: .regularExpression)
            if !["the morning", "the evening", "the afternoon", "my area", "here"].contains(tail) { place = tail }
        }
        return WeatherAsk(place: place, day: l.contains("tomorrow") ? 1 : 0, sun: l.contains("sunrise") || l.contains("sunset"))
    }

    static func weather(_ ask: WeatherAsk) async -> Hit? {
        guard let spot = await Locator.shared.spot(named: ask.place) else {
            return Hit(id: "weather", icon: .symbol("location.slash"), title: "Where are you?",
                       subtitle: "Allow Location for Gus, or ask “weather in <city>”", hint: "Open", group: .answer,
                       score: 100, big: true,
                       run: { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!) })
        }
        guard let w = await Forecast.fetch(lat: spot.lat, lon: spot.lon) else { return nil }
        let i = min(ask.day, w.days.count - 1)
        let day = w.days[i]
        let deg = "°"
        if ask.sun {
            let f = DateFormatter(); f.timeStyle = .short; f.timeZone = TimeZone(identifier: w.timeZone)
            let title = "↑ \(f.string(from: day.sunrise))   ↓ \(f.string(from: day.sunset))"
            return Hit(id: "weather", icon: .symbol("sun.horizon"), title: title,
                       subtitle: "\(spot.name) · sunrise and sunset \(ask.day == 1 ? "tomorrow" : "today")", hint: "Copy",
                       group: .answer, score: 100, big: true, run: { Pasteboard.copy(title) }, copyText: title)
        }
        let (text, symbol) = Forecast.describe(ask.day == 0 ? w.code : day.code)
        let title = ask.day == 0 ? "\(Int(w.temp.rounded()))\(deg) · \(text)" : "\(Int(day.high.rounded()))\(deg) · \(text)"
        var bits = [spot.name]
        if ask.day == 0 { bits.append("feels \(Int(w.feels.rounded()))\(deg)") } else { bits.append("tomorrow") }
        bits.append("H \(Int(day.high.rounded()))\(deg) L \(Int(day.low.rounded()))\(deg)")
        if day.rain > 0 { bits.append("rain \(day.rain)%") }
        return Hit(id: "weather", icon: .symbol(symbol), title: title, subtitle: bits.joined(separator: " · "), hint: "Open",
                   group: .answer, score: 100, big: true,
                   run: {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.weather") {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
        }, copyText: "\(title), \(spot.name)")
    }
}

// MARK: - Where you are

@MainActor
final class Locator: NSObject, CLLocationManagerDelegate {
    static let shared = Locator()
    struct Spot { let lat: Double; let lon: Double; let name: String }
    private let manager = CLLocationManager()
    private var cached: (Spot, Date)?
    private var waiting: [CheckedContinuation<Spot?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func spot(named place: String?) async -> Spot? {
        if let place { return await geocode(place) }
        if let (s, t) = cached, Date().timeIntervalSince(t) < 3600 { return s }
        switch manager.authorizationStatus {
        case .denied, .restricted: return await fallback()
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: break
        }
        manager.requestLocation()
        let found: Spot? = await withCheckedContinuation { c in
            waiting.append(c)
            Task { try? await Task.sleep(nanoseconds: 6_000_000_000); self.finish(nil) }
        }
        if let found { return found }
        return await fallback()
    }

    /// No location: the city of your time zone ("Asia/Kolkata" → Kolkata) is a fair guess.
    private func fallback() async -> Spot? {
        guard let city = TimeZone.current.identifier.split(separator: "/").last else { return nil }
        return await geocode(city.replacingOccurrences(of: "_", with: " "))
    }

    private func finish(_ spot: Spot?) {
        let w = waiting; waiting = []
        w.forEach { $0.resume(returning: spot) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            let name = (try? await CLGeocoder().reverseGeocodeLocation(loc))?.first.flatMap { $0.locality ?? $0.name } ?? "Here"
            // Rounded to about a kilometre before it leaves the Mac.
            let s = Spot(lat: (loc.coordinate.latitude * 100).rounded() / 100, lon: (loc.coordinate.longitude * 100).rounded() / 100, name: name)
            self.cached = (s, Date())
            self.finish(s)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let s = manager.authorizationStatus
            if s == .authorizedAlways || s == .authorized { manager.requestLocation() }
            else if s == .denied || s == .restricted { self.finish(nil) }
        }
    }

    private func geocode(_ place: String) async -> Spot? {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [URLQueryItem(name: "name", value: place), URLQueryItem(name: "count", value: "1")]
        guard let url = c.url, let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (json["results"] as? [[String: Any]])?.first,
              let lat = first["latitude"] as? Double, let lon = first["longitude"] as? Double else { return nil }
        return Spot(lat: lat, lon: lon, name: first["name"] as? String ?? place.capitalized)
    }
}

// MARK: - Forecast (Open-Meteo)

enum Forecast {
    struct Day { let high: Double; let low: Double; let rain: Int; let code: Int; let sunrise: Date; let sunset: Date }
    struct Weather { let temp: Double; let feels: Double; let code: Int; let timeZone: String; let days: [Day] }

    nonisolated(unsafe) private static var cache: [String: (Weather, Date)] = [:]

    static func fetch(lat: Double, lon: Double) async -> Weather? {
        let key = "\(lat),\(lon)"
        if let (w, t) = cache[key], Date().timeIntervalSince(t) < 900 { return w }
        let fahrenheit = Region.locale.measurementSystem == .us
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)), URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code,sunrise,sunset"),
            URLQueryItem(name: "timezone", value: "auto"), URLQueryItem(name: "forecast_days", value: "3"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
        ]
        guard let url = c.url, let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cur = json["current"] as? [String: Any], let daily = json["daily"] as? [String: Any],
              let tz = json["timezone"] as? String else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm"; f.timeZone = TimeZone(identifier: tz)
        let highs = daily["temperature_2m_max"] as? [Double] ?? [], lows = daily["temperature_2m_min"] as? [Double] ?? []
        let rains = daily["precipitation_probability_max"] as? [Int] ?? [], codes = daily["weather_code"] as? [Int] ?? []
        let rises = daily["sunrise"] as? [String] ?? [], sets = daily["sunset"] as? [String] ?? []
        var days: [Day] = []
        for i in 0..<min(highs.count, lows.count, codes.count, rises.count, sets.count) {
            days.append(Day(high: highs[i], low: lows[i], rain: i < rains.count ? rains[i] : 0, code: codes[i],
                            sunrise: f.date(from: rises[i]) ?? Date(), sunset: f.date(from: sets[i]) ?? Date()))
        }
        guard !days.isEmpty, let temp = cur["temperature_2m"] as? Double else { return nil }
        let w = Weather(temp: temp, feels: cur["apparent_temperature"] as? Double ?? temp,
                        code: cur["weather_code"] as? Int ?? days[0].code, timeZone: tz, days: days)
        cache[key] = (w, Date())
        return w
    }

    /// WMO weather codes in plain words, with a matching SF Symbol.
    static func describe(_ code: Int) -> (String, String) {
        switch code {
        case 0: return ("Clear", "sun.max")
        case 1: return ("Mostly clear", "sun.max")
        case 2: return ("Partly cloudy", "cloud.sun")
        case 3: return ("Cloudy", "cloud")
        case 45, 48: return ("Fog", "cloud.fog")
        case 51, 53, 55, 56, 57: return ("Drizzle", "cloud.drizzle")
        case 61, 63, 80, 81: return ("Rain", "cloud.rain")
        case 65, 82: return ("Heavy rain", "cloud.heavyrain")
        case 66, 67: return ("Freezing rain", "cloud.sleet")
        case 71, 73, 75, 77, 85, 86: return ("Snow", "cloud.snow")
        case 95: return ("Thunderstorms", "cloud.bolt.rain")
        case 96, 99: return ("Thunderstorms with hail", "cloud.bolt.rain")
        default: return ("Weather", "cloud.sun")
        }
    }
}
