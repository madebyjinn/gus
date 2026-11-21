import SwiftUI
import AppKit
import ServiceManagement
import Contacts
import EventKit

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    enum Look: String, CaseIterable { case solid = "Solid", glass = "Liquid Glass", gus = "Gus"
        @MainActor static var available: [Look] { allCases }
    }
    enum Appearance: String, CaseIterable { case system = "System", light = "Light", dark = "Dark", inverted = "Inverted" }
    enum ContactTab: String, CaseIterable { case call = "Call", message = "Message" }
    enum CopyModifier: String, CaseIterable { case option = "⌥C", control = "⌃C", shiftCommand = "⇧⌘C"
        var flags: NSEvent.ModifierFlags {
            switch self { case .option: return .option; case .control: return .control; case .shiftCommand: return [.shift, .command] }
        }
    }

    @Published var look: Look { didSet { d.set(look.rawValue, forKey: "look"); Z.glass = look == .glass; Z.gus = look == .gus; onAppearance() } }
    @Published var appearance: Appearance { didSet { d.set(appearance.rawValue, forKey: "appearance"); onAppearance() } }
    @Published var accent: ZAccent { didSet { d.set(accent.rawValue, forKey: ZAccent.key); Z.accentChoice = accent } }
    @Published var hotkey: Hotkey.Combo { didSet { if let data = try? JSONEncoder().encode(hotkey) { d.set(data, forKey: "hotkey") }; onHotkey(hotkey) } }
    @Published var notesHotkey: Hotkey.Combo { didSet { if let data = try? JSONEncoder().encode(notesHotkey) { d.set(data, forKey: "notesHotkey") }; onNotesHotkey(notesHotkey) } }
    @Published var clipboardHistory: Bool { didSet { d.set(clipboardHistory, forKey: "clipboardHistory") } }
    @Published var pasteDirectly: Bool { didSet { d.set(pasteDirectly, forKey: "pasteDirectly"); if pasteDirectly && !AXIsProcessTrusted() { Pasteboard.askForAccessibility() } } }
    @Published var contactTab: ContactTab { didSet { d.set(contactTab == .message ? "message" : "call", forKey: "contactTab") } }
    /// A region code ("IN", "US"), or empty to follow the Mac.
    @Published var region: String { didSet { d.set(region, forKey: "region") } }
    @Published var folders: [String] { didSet { d.set(folders, forKey: "indexedFolders"); reindex() } }
    /// Off until you turn it on: no folders are read before then.
    @Published var searchFiles: Bool { didSet { d.set(searchFiles, forKey: "searchFiles"); reindex() } }
    @Published var copyModifier: CopyModifier { didSet { d.set(copyModifier.rawValue, forKey: "copyModifier") } }
    @Published var indexed = 0
    @Published var openAtLogin = SMAppService.mainApp.status == .enabled
    /// Seconds after closing that the bar forgets what was typed. 0 keeps it until you clear it.
    @Published var freshAfter: Double { didSet { d.set(freshAfter, forKey: "freshAfter") } }

    /// Who answers questions (Settings › Advanced). Keys are kept in the Keychain.
    @Published var engine: Engine { didSet { d.set(engine.rawValue, forKey: "engine"); Assistant.shared.clearAnswer() } }
    @Published var openAIKey: String { didSet { Keychain.write("openai-key", openAIKey) } }
    @Published var claudeKey: String { didSet { Keychain.write("claude-key", claudeKey) } }
    @Published var openAIModel: String { didSet { d.set(openAIModel, forKey: "openAIModel") } }
    @Published var claudeModel: String { didSet { d.set(claudeModel, forKey: "claudeModel") } }
    static let storeURL = URL(string: "https://madebyjinn.com/gus")!
    static let defaultOpenAIModel = "gpt-6.1-sol"
    static let defaultClaudeModel = "claude-opus-5-5"

    var onHotkey: (Hotkey.Combo) -> Void = { _ in }
    var onNotesHotkey: (Hotkey.Combo) -> Void = { _ in }
    var onAppearance: () -> Void = {}

    private init() {
        var startLook = Look(rawValue: d.string(forKey: "look") ?? "") ?? .solid
        switch ProcessInfo.processInfo.environment["GUS_LOOK"] {
        case "glass": startLook = .glass
        case "gus": startLook = .gus
        case "solid": startLook = .solid
        default: break
        }
        look = startLook
        appearance = Appearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        accent = Z.accentChoice
        hotkey = (d.data(forKey: "hotkey")).flatMap { try? JSONDecoder().decode(Hotkey.Combo.self, from: $0) } ?? .optionSpace
        notesHotkey = (d.data(forKey: "notesHotkey")).flatMap { try? JSONDecoder().decode(Hotkey.Combo.self, from: $0) } ?? .controlOptionN
        clipboardHistory = d.object(forKey: "clipboardHistory") as? Bool ?? true
        pasteDirectly = d.object(forKey: "pasteDirectly") as? Bool ?? true
        contactTab = d.string(forKey: "contactTab") == "message" ? .message : .call
        region = d.string(forKey: "region") ?? ""
        freshAfter = d.object(forKey: "freshAfter") as? Double ?? 30
        folders = d.stringArray(forKey: "indexedFolders") ?? FileIndex.defaultRoots
        searchFiles = d.bool(forKey: "searchFiles")
        copyModifier = CopyModifier(rawValue: d.string(forKey: "copyModifier") ?? "") ?? .option
        engine = Engine(rawValue: d.string(forKey: "engine") ?? "") ?? .apple
        openAIKey = Keychain.read("openai-key")
        claudeKey = Keychain.read("claude-key")
        openAIModel = d.string(forKey: "openAIModel") ?? Settings.defaultOpenAIModel
        claudeModel = d.string(forKey: "claudeModel") ?? Settings.defaultClaudeModel
        Z.glass = startLook == .glass
        Z.gus = startLook == .gus
    }

    func reindex() {
        FileIndex.shared.rebuild(searchFiles ? folders : []) { n in
            Task { @MainActor in Settings.shared.indexed = n }
        }
    }

    func setOpenAtLogin(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
        openAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// The bar's appearance for the Mac's current one: Inverted is the opposite (a dark bar on a light Mac).
    func barAppearance(systemIsDark: Bool) -> NSAppearance? {
        switch appearance {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .inverted: return NSAppearance(named: systemIsDark ? .aqua : .darkAqua)
        }
    }
}

/// Settings live inside the bar (⌘S), as sections of rows. Typing filters them.
struct SettingsPane: View {
    let filter: String
    @ObservedObject var settings = Settings.shared
    @ObservedObject var contacts = ContactSearch.shared
    @ObservedObject var history = ClipboardHistory.shared
    @State private var calendarStatus = EKEventStore.authorizationStatus(for: .event)
    @State private var remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
    @State private var trusted = AXIsProcessTrusted()


    private func shows(_ words: String...) -> Bool {
        let f = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return f.isEmpty || words.contains { $0.lowercased().contains(f) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if shows("look", "appearance", "dark", "light", "theme", "glass", "accent", "colour", "color") {
                ZSection(title: "Look", symbol: "circle.lefthalf.filled") {
                    ChoiceRow(title: "Appearance",
                              caption: settings.appearance == .inverted ? "A dark bar on a light Mac, a light bar on a dark one"
                                : settings.appearance == .system ? "Follows the Mac" : "Always \(settings.appearance.rawValue.lowercased())") {
                        ZSegmented(title: "Appearance", selection: $settings.appearance, options: Settings.Appearance.allCases) { $0.rawValue }
                    }
                    ChoiceRow(title: "Material", caption: nil) {
                        ZSegmented(title: "Material", selection: $settings.look, options: Settings.Look.available) { $0.rawValue }
                    }
                    ZRow(symbol: "paintpalette", title: "Accent") { AccentDots(selection: $settings.accent) }
                }
            }

            if shows("shortcut", "hotkey", "key", "space", "copy", "notes") {
                ZSection(title: "Shortcut", symbol: "command") {
                    ChoiceRow(title: "Open Gus",
                              caption: settings.hotkey == .commandSpace
                                ? "Turn off Spotlight's ⌘Space first: System Settings › Keyboard › Keyboard Shortcuts › Spotlight"
                                : "Opens Gus from anywhere. ⇥ clipboard · ⌘S settings · Esc hides") {
                        ZSegmented(title: "Shortcut", selection: $settings.hotkey, options: Hotkey.Combo.all) { $0.label }
                    }
                    ZRow(symbol: "note.text", title: "Floating notes", subtitle: "Shows and hides your notes; text in the bar goes with it") {
                        ZSegmented(title: "Notes shortcut", selection: $settings.notesHotkey, options: Hotkey.Combo.notes) { $0.label }
                            .frame(width: Z.glass ? nil : 210)
                    }
                    ZRow(symbol: "doc.on.doc", title: "Copy key", subtitle: "Copies the contact, clip or answer under the pointer") {
                        ZSegmented(title: "Copy key", selection: $settings.copyModifier, options: Settings.CopyModifier.allCases) { $0.rawValue }
                            .frame(width: Z.glass ? nil : 170)
                    }
                }
            }

            if shows("files", "folders", "index") {
                ZSection(title: "Files and folders", symbol: "folder",
                         footer: settings.searchFiles ? "\(settings.indexed.formatted()) items indexed. Gus reads names only, on this Mac."
                                                      : "Off: Gus doesn't read any folders.") {
                    ZRow(symbol: "magnifyingglass", title: "Search files and folders", subtitle: "Indexes the folders below") {
                        Toggle("", isOn: $settings.searchFiles).zToggle()
                    }
                    if settings.searchFiles {
                    ForEach(settings.folders, id: \.self) { folder in
                        ZRow(symbol: "folder", title: (folder as NSString).lastPathComponent,
                             subtitle: folder.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                            Button("Remove") { settings.folders.removeAll { $0 == folder } }.zButton(.secondary)
                        }
                    }
                    ZRow(symbol: "plus", title: "Add a folder", subtitle: "Pick what Gus should find") {
                        Button("Add…") { FolderPicker.pick { settings.folders.append(contentsOf: $0.filter { !settings.folders.contains($0) }) } }
                            .zButton(.secondary)
                    }
                    }
                }
            }

            if shows("contacts", "calendar", "reminders", "intelligence", "siri", "access", "privacy", "call", "message") {
                ZSection(title: "People and plans", symbol: "person.2") {
                    access("person.crop.circle", "Contacts", "Find people as you type", allowed: contacts.allowed,
                           undecided: contacts.status == .notDetermined) { contacts.requestAccess() }
                    ZRow(symbol: "phone", title: "Tab on a contact", subtitle: settings.contactTab == .call ? "Calls them" : "Opens Messages") {
                        ZSegmented(title: "Tab on a contact", selection: $settings.contactTab, options: Settings.ContactTab.allCases) { $0.rawValue }
                            .frame(width: Z.glass ? nil : 150)
                    }
                    access("calendar", "Calendar", "“today”, “tomorrow”, “calendar friday”", allowed: calendarStatus == .fullAccess,
                           undecided: calendarStatus == .notDetermined) {
                        Assistant.shared.requestCalendar { calendarStatus = EKEventStore.authorizationStatus(for: .event) }
                    }
                    access("checklist", "Reminders", "“remind me to call mum at 5”", allowed: remindersStatus == .fullAccess,
                           undecided: remindersStatus == .notDetermined) {
                        Task {
                            _ = try? await Assistant.shared.store.requestFullAccessToReminders()
                            remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
                        }
                    }
                    ZRow(symbol: settings.engine.symbol, title: "Ask Gus",
                         subtitle: Assistant.shared.canAsk ? "End a question with ? and press Return"
                            : settings.engine == .apple ? "Not available on this Mac" : "Finish setting it up under Advanced",
                         dimmed: !Assistant.shared.canAsk) { EmptyView() }
                }
            }

            if shows("clipboard", "history", "paste", "copy") {
                ZSection(title: "Clipboard", symbol: "doc.on.clipboard",
                         footer: "Kept on this Mac only. Password managers' copies are skipped.") {
                    ZRow(symbol: "clock.arrow.circlepath", title: "Keep history", subtitle: "\(history.clips.count) items") {
                        Toggle("", isOn: $settings.clipboardHistory).zToggle()
                    }
                    ZRow(symbol: "arrow.down.doc", title: "Return pastes",
                         subtitle: trusted ? "Into the app and field you were in" : "Needs Accessibility; without it, Return copies") {
                        Toggle("", isOn: $settings.pasteDirectly).zToggle()
                    }
                    ZRow(symbol: "trash", title: "Clear history") {
                        Button("Clear") { history.clear() }.zButton(.danger)
                    }
                }
            }

            if shows("region", "country", "currency", "money", "convert", "units", "temperature", "weather") {
                ZSection(title: "Region", symbol: "globe",
                         footer: "Gus uses this for things that depend on where you are: the currency amounts convert to, and °C or °F for the weather.") {
                    ZRow(symbol: "location", title: "Default region",
                         subtitle: "\(settings.region.isEmpty ? "From this Mac: " : "")\(Region.name(Region.locale.region?.identifier ?? "")) · converts to \(Currency.local)") {
                        Picker("", selection: $settings.region) {
                            Text("Automatic").tag("")
                            Divider()
                            ForEach(Region.all, id: \.self) { Text(Region.name($0)).tag($0) }
                        }
                        .labelsHidden().frame(width: 170).controlSize(.small)
                    }
                }
            }

            if shows("general", "login", "quit", "startup", "fresh", "reset", "remember", "support", "buy", "open source") {
                ZSection(title: "General", symbol: "gearshape") {
                    ZRow(symbol: "arrow.counterclockwise", title: "Start fresh",
                         subtitle: settings.freshAfter == 0 ? "Gus keeps what you typed until you clear it" : "Clears what you typed once Gus's been closed a while") {
                        ZSegmented(title: "Start fresh", selection: $settings.freshAfter, options: [30, 120, 600, 0]) {
                            $0 == 0 ? "Never" : $0 < 60 ? "\(Int($0)) s" : "\(Int($0) / 60) min"
                        }
                        .frame(width: 230)
                    }
                    ZRow(symbol: "power", title: "Open at login") {
                        Toggle("", isOn: Binding(get: { settings.openAtLogin }, set: { settings.setOpenAtLogin($0) })).zToggle()
                    }
                    ZRow(symbol: "hand.wave", title: "Welcome tour", subtitle: "Gus shows you around") {
                        Button("Show") { Launcher.shared.startWelcome() }.zButton(.secondary)
                    }
                    ZRow(symbol: "heart", title: "Support Gus", subtitle: "Gus is open source. Buying it keeps him fed") {
                        Button("Buy…") { NSWorkspace.shared.open(Settings.storeURL) }.zButton(.secondary)
                    }
                    ZRow(symbol: "xmark.circle", title: "Quit Gus",
                         subtitle: "Gus \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")") {
                        Button("Quit") { NSApp.terminate(nil) }.zButton(.filled)
                    }
                }
            }

            if shows("advanced", "powered", "gus", "answers", "openai", "chatgpt", "claude", "codex", "api key", "model", "intelligence", "ai") {
                advanced
            }
        }
        .padding(Z.glass ? 16 : 14)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trusted = AXIsProcessTrusted()
            calendarStatus = EKEventStore.authorizationStatus(for: .event)
            remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
        }
    }

    /// Last in the list, under its own heading: most people never need it.
    @ViewBuilder
    private var advanced: some View {
        ZSection(title: "Advanced", symbol: "slider.horizontal.3",
                 footer: "Sums, conversions, weather and reminders always stay on this Mac. Only a question you ask Gus goes to the service you pick.") {
            ZRow(symbol: settings.engine.symbol, title: "Gus is powered by", subtitle: engineStatus) {
                Picker("", selection: $settings.engine) {
                    ForEach(Engine.allCases) { Text($0.choice).tag($0) }
                }
                .labelsHidden().frame(width: 190).controlSize(.small)
            }
            switch settings.engine {
            case .openai:
                ZRow(symbol: "key", title: "API key", subtitle: "From platform.openai.com. Kept in your Keychain") {
                    SettingField(placeholder: "sk-…", text: $settings.openAIKey, secure: true)
                }
                ZRow(symbol: "cpu", title: "Model", subtitle: "Billed to your OpenAI account") {
                    SettingField(placeholder: Settings.defaultOpenAIModel, text: $settings.openAIModel, secure: false)
                }
            case .claude:
                ZRow(symbol: "key", title: "API key", subtitle: "From platform.claude.com. Kept in your Keychain") {
                    SettingField(placeholder: "sk-ant-…", text: $settings.claudeKey, secure: true)
                }
                ZRow(symbol: "cpu", title: "Model", subtitle: "Billed to your Claude API account") {
                    SettingField(placeholder: Settings.defaultClaudeModel, text: $settings.claudeModel, secure: false)
                }
            case .apple, .codex, .claudeCode:
                EmptyView()
            }
        }
    }

    private var engineStatus: String {
        switch settings.engine {
        case .apple: return Assistant.shared.modelAvailable ? "On this Mac, private and free" : "Not available on this Mac"
        case .openai: return settings.openAIKey.isEmpty ? "Paste a key to start" : "Ready"
        case .claude: return settings.claudeKey.isEmpty ? "Paste a key to start" : "Ready"
        case .codex: return RemoteChat.tool(.codex) == nil ? "Codex isn't installed on this Mac" : "Uses your ChatGPT plan, through Codex"
        case .claudeCode: return RemoteChat.tool(.claudeCode) == nil ? "Claude Code isn't installed on this Mac" : "Uses your Claude plan, through Claude Code"
        }
    }

    @ViewBuilder
    private func access(_ symbol: String, _ title: String, _ subtitle: String, allowed: Bool, undecided: Bool,
                        ask: @escaping () -> Void) -> some View {
        ZRow(symbol: symbol, title: title, subtitle: subtitle) {
            if allowed {
                Text("Allowed").font(Z.Font.button).foregroundStyle(Z.ink2)
            } else if undecided {
                Button("Allow") { ask() }.zButton(.secondary)
            } else {
                Button("Open Privacy…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
                }.zButton(.secondary)
            }
        }
    }
}

/// A small text box in a settings row: an API key (hidden) or a model name. While it has the keyboard,
/// the bar leaves ⌫ alone.
struct SettingField: View {
    let placeholder: String
    @Binding var text: String
    let secure: Bool
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) }
        }
        .focused($focused)
        .autocorrectionDisabled()
        .modifier(Box(glass: Z.glass, focused: focused))
        .frame(width: 190)
        .onChange(of: focused) { _, on in Launcher.shared.typingInSettings = on }
        .onDisappear { Launcher.shared.typingInSettings = false }
    }

    private struct Box: ViewModifier {
        let glass: Bool
        let focused: Bool
        func body(content: Content) -> some View {
            if glass {
                content.textFieldStyle(.roundedBorder).controlSize(.small)
            } else {
                content.textFieldStyle(.plain).font(.system(size: 12, design: .monospaced)).foregroundStyle(Z.ink)
                    .padding(.horizontal, 8).frame(height: 26)
                    .background(Z.rect(Z.Radius.md).fill(Z.surface))
                    .overlay(Z.rect(Z.Radius.md).strokeBorder(focused ? Z.accent.opacity(0.6) : Z.hairlineStrong, lineWidth: 1))
            }
        }
    }
}

/// A choice between a few options. Solid: the segmented control across the card with its caption under
/// it. Liquid Glass: a form row as in System Settings, label and caption on the left, control on the right.
struct ChoiceRow<Control: View>: View {
    let title: String
    let caption: String?
    @ViewBuilder var control: Control

    var body: some View {
        if Z.glass {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body).foregroundStyle(.primary)
                    if let caption {
                        Text(caption).font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                control.fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: caption == nil ? 34 : 44)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                control
                if let caption {
                    Text(caption).font(Z.Font.caption).foregroundStyle(Z.ink2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Z.Space.md)
        }
    }
}

/// The folder chooser. The bar steps aside while it's open, then comes back on settings.
@MainActor
enum FolderPicker {
    static var willPick: () -> Void = {}
    static var didPick: () -> Void = {}
    static func pick(_ done: @escaping ([String]) -> Void) {
        willPick()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Index"
        panel.message = "Gus will find the files and folders inside."
        NSApp.activate(ignoringOtherApps: true)
        let result = panel.runModal()
        if result == .OK { done(panel.urls.map(\.path)) }
        didPick()
    }
}

struct AccentDots: View {
    @Binding var selection: ZAccent
    var body: some View {
        HStack(spacing: 7) {
            ForEach(ZAccent.allCases) { accent in
                let on = accent == selection
                Button { withAnimation(Z.Motion.snap) { selection = accent } } label: {
                    Circle().fill(accent.color)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                        .overlay { if on { Circle().fill(Color.white).frame(width: 5, height: 5) } }
                        .frame(width: 14, height: 14).padding(2)
                        .overlay(Circle().strokeBorder(on ? accent.color.opacity(0.55) : .clear, lineWidth: 1.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain).help(accent.rawValue)
            }
        }
    }
}
