import AppIntents
import AppKit

// Gus's actions for Siri, Spotlight and Shortcuts: "Open Gus", "Show my clipboard in Gus",
// "Convert 20 dollars with Gus". With Apple Intelligence, Siri can chain these with its own actions.

struct OpenGus: AppIntent {
    static let title: LocalizedStringResource = "Open Gus"
    static let description = IntentDescription("Opens the Gus search bar.")
    @MainActor func perform() async throws -> some IntentResult {
        Launcher.shared.show()
        return .result()
    }
}

struct ShowClipboard: AppIntent {
    static let title: LocalizedStringResource = "Show Clipboard History"
    static let description = IntentDescription("Opens Gus on your clipboard history.")
    @MainActor func perform() async throws -> some IntentResult {
        Launcher.shared.show()
        if Launcher.shared.mode != .clipboard { Launcher.shared.toggleClipboard() }
        return .result()
    }
}

struct SearchGus: AppIntent {
    static let title: LocalizedStringResource = "Search with Gus"
    @Parameter(title: "Text") var text: String
    @MainActor func perform() async throws -> some IntentResult {
        Launcher.shared.show()
        Launcher.shared.query = text
        return .result()
    }
}

struct ConvertCurrency: AppIntent {
    static let title: LocalizedStringResource = "Convert Currency"
    static let description = IntentDescription("Converts an amount to your local currency at today's rate.")
    @Parameter(title: "Amount") var amount: Double
    @Parameter(title: "From", description: "A currency code, like USD") var from: String
    @Parameter(title: "To", description: "Leave empty for your currency") var to: String?

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        Rates.shared.refreshIfStale()
        let source = from.uppercased()
        let target = (to?.uppercased()).flatMap { $0.isEmpty ? nil : $0 } ?? Currency.local
        guard let value = Rates.shared.convert(amount, from: source, to: target) else {
            return .result(value: "", dialog: "Gus doesn't have rates for \(source) to \(target) yet.")
        }
        let shown = Currency.format(value, target)
        return .result(value: shown, dialog: "\(Currency.format(amount, source)) is \(shown).")
    }
}

struct GusShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenGus(), phrases: ["Open \(.applicationName)", "Search with \(.applicationName)"],
                    shortTitle: "Open Gus", systemImageName: "magnifyingglass")
        AppShortcut(intent: ShowClipboard(), phrases: ["Show my clipboard in \(.applicationName)",
                                                       "Open clipboard history in \(.applicationName)"],
                    shortTitle: "Clipboard", systemImageName: "doc.on.clipboard")
        AppShortcut(intent: ConvertCurrency(), phrases: ["Convert currency with \(.applicationName)"],
                    shortTitle: "Convert Currency", systemImageName: "dollarsign.arrow.circlepath")
    }
}
