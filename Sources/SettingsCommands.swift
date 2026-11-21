import AppKit

/// Settings you can flip by typing: "dark mode", "liquid glass", "open at login", "file search",
/// "accent plum", "clear clipboard"… Each shows as a result with its current state; Return flips it and
/// the bar stays open so you can see it happen.
@MainActor
enum SettingsCommands {
    private struct Command {
        let id: String
        let keywords: [String]
        let symbol: String
        let title: String
        let state: String
        let verb: String
        let run: @MainActor () -> Void
    }

    static func hits(_ q: String) -> [Hit] {
        let l = q.lowercased().trimmingCharacters(in: .whitespaces)
        guard l.count >= 3 else { return [] }
        let found = commands().filter { c in
            c.keywords.contains { k in k.hasPrefix(l) || (l.count >= 4 && l.contains(k)) }
        }
        return found.prefix(5).enumerated().map { i, c in
            Hit(id: "set:" + c.id, icon: .symbol(c.symbol), title: c.title, subtitle: "Gus setting · " + c.state,
                hint: c.verb, group: .apps, score: 88 - Double(i),
                run: {
                    c.run()
                    Launcher.shared.refresh()
                })
        }
    }

    private static func commands() -> [Command] {
        let s = Settings.shared
        var list: [Command] = []

        func appearance(_ a: Settings.Appearance, _ keys: [String], _ symbol: String) {
            let on = s.appearance == a
            list.append(Command(id: "appearance." + a.rawValue, keywords: keys, symbol: symbol,
                                title: a == .system ? "Match the Mac's Appearance" : "\(a.rawValue) Mode",
                                state: on ? "on now" : "now \(s.appearance.rawValue)", verb: on ? "On" : "Switch",
                                run: { Settings.shared.appearance = a; Launcher.shared.say("\(a.rawValue) appearance") }))
        }
        appearance(.dark, ["dark mode", "dark theme", "dark appearance", "night mode"], "moon")
        appearance(.light, ["light mode", "light theme", "light appearance", "day mode"], "sun.max")
        appearance(.system, ["system appearance", "auto appearance", "automatic appearance", "match system", "system mode"], "circle.lefthalf.filled")
        appearance(.inverted, ["inverted mode", "inverted appearance", "invert appearance"], "circle.righthalf.filled")

        for look in Settings.Look.available {
            let on = s.look == look
            let keys: [String]
            switch look {
            case .solid: keys = ["solid theme", "solid look", "solid material"]
            case .glass: keys = ["liquid glass", "glass theme", "glass look", "glass material"]
            case .gus: keys = ["gus theme", "gus look", "otter theme", "otter look", "speech bubble", "butler theme"]
            }
            list.append(Command(id: "look." + look.rawValue, keywords: keys,
                                symbol: look == .glass ? "square.on.square" : look == .gus ? "bubble.left" : "square",
                                title: "\(look.rawValue) Look", state: on ? "on now" : "now \(s.look.rawValue)",
                                verb: on ? "On" : "Switch",
                                run: { Settings.shared.look = look; Launcher.shared.say("\(look.rawValue) look") }))
        }

        func toggle(_ id: String, _ keys: [String], _ symbol: String, _ title: String, _ value: Bool, _ set: @escaping @MainActor (Bool) -> Void) {
            list.append(Command(id: id, keywords: keys, symbol: symbol, title: title, state: value ? "on" : "off",
                                verb: value ? "Turn Off" : "Turn On",
                                run: { set(!value); Launcher.shared.say("\(title) \(value ? "off" : "on")") }))
        }
        toggle("login", ["open at login", "launch at login", "start at login", "login item", "startup"], "power",
               "Open at Login", s.openAtLogin) { Settings.shared.setOpenAtLogin($0) }
        toggle("files", ["file search", "search files", "index files", "files and folders", "folder search"], "folder",
               "Search Files and Folders", s.searchFiles) { Settings.shared.searchFiles = $0 }
        toggle("history", ["clipboard history", "keep clipboard", "clipboard on", "clipboard off"], "clock.arrow.circlepath",
               "Clipboard History", s.clipboardHistory) { Settings.shared.clipboardHistory = $0 }
        toggle("paste", ["paste on return", "return pastes", "paste directly", "auto paste"], "arrow.down.doc",
               "Return Pastes Clipboard Items", s.pasteDirectly) { Settings.shared.pasteDirectly = $0 }

        let message = s.contactTab == .message
        list.append(Command(id: "contactTab", keywords: ["tab on contact", "tab calls", "tab messages", "contact tab"], symbol: "phone",
                            title: message ? "Tab Calls a Contact" : "Tab Messages a Contact",
                            state: "now \(s.contactTab.rawValue.lowercased())s", verb: "Switch",
                            run: { Settings.shared.contactTab = message ? .call : .message }))

        for accent in ZAccent.allCases {
            let name = accent.rawValue.lowercased()
            let on = s.accent == accent
            list.append(Command(id: "accent." + name, keywords: ["accent " + name, name + " accent", "accent colour " + name, "accent color " + name],
                                symbol: "paintpalette", title: "\(accent.rawValue) Accent",
                                state: on ? "on now" : "now \(s.accent.rawValue)", verb: on ? "On" : "Switch",
                                run: { Settings.shared.accent = accent; Launcher.shared.say("\(accent.rawValue) accent") }))
        }

        list.append(Command(id: "clearClipboard", keywords: ["clear clipboard", "clear history", "empty clipboard", "delete clipboard history"],
                            symbol: "trash", title: "Clear Clipboard History",
                            state: "\(ClipboardHistory.shared.clips.count) items", verb: "Clear",
                            run: { ClipboardHistory.shared.clear(); Launcher.shared.say("Clipboard history cleared") }))
        list.append(Command(id: "tour", keywords: ["welcome tour", "show welcome", "onboarding", "gus tour"], symbol: "hand.wave",
                            title: "Welcome Tour", state: "with Gus", verb: "Show",
                            run: { Launcher.shared.startWelcome() }))
        list.append(Command(id: "quit", keywords: ["quit gus", "exit gus"], symbol: "xmark.circle", title: "Quit Gus",
                            state: "closes the app", verb: "Quit", run: { NSApp.terminate(nil) }))
        return list
    }
}
