import AppKit
import SwiftUI

@main
struct GusApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = MainActor.assumeIsolated { AppDelegate() }
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class BarWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// One window, made at launch and kept: showing it is ordering it front, so the bar is there the instant
/// the shortcut lands. Its size never changes; the card inside animates its own height.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: BarWindow!
    private var item: NSStatusItem!
    private var hotkey: Hotkey?
    private var notesHotkey: Hotkey?
    private var otter: MenuOtter?
    private var monitors: [Any] = []
    private var hideWork: DispatchWorkItem?
    /// When the bar was last put away: after a while it opens fresh instead of where you left off.
    private var hiddenAt: Date?
    private var previousApp: NSRunningApplication?
    private var appearanceWatch: NSKeyValueObservation?

    static let margin: CGFloat = 40

    /// Gus used to be called Peel. Once, on first run, bring over its settings and its folder (clipboard
    /// history, notes, rates) so nothing is lost in the rename.
    static func adoptPeel() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "adoptedPeel") else { return }
        if let old = UserDefaults(suiteName: "com.madebyjinn.peel")?.persistentDomain(forName: "com.madebyjinn.peel") {
            for (k, v) in old where d.object(forKey: k) == nil && !k.hasPrefix("NS") { d.set(v, forKey: k) }
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let from = support.appendingPathComponent("Peel"), to = support.appendingPathComponent("Gus")
        if FileManager.default.fileExists(atPath: from.path), !FileManager.default.fileExists(atPath: to.path) {
            try? FileManager.default.copyItem(at: from, to: to)
        }
        d.set(true, forKey: "adoptedPeel")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.adoptPeel()
        let env = ProcessInfo.processInfo.environment
        if let look = env["GUS_APPEARANCE"] { NSApp.appearance = NSAppearance(named: look == "dark" ? .darkAqua : .aqua) }

        let size = NSSize(width: BarCard.width + Self.margin * 2, height: 800)
        window = BarWindow(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .modalPanel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        let host = NSHostingView(rootView: BarShell(margin: Self.margin)
            .environmentObject(Launcher.shared).environmentObject(Settings.shared))
        host.sizingOptions = []
        window.contentView = host

        installMainMenu()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        otter = MenuOtter(button: item.button)
        NotificationCenter.default.addObserver(forName: .gusCopied, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.otter?.copied() }
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Gus", action: #selector(openBar), keyEquivalent: "")
        menu.addItem(withTitle: "Clipboard", action: #selector(openClipboard), keyEquivalent: "")
        menu.addItem(withTitle: "Floating Notes", action: #selector(openNotesMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Welcome Tour", action: #selector(openWelcome), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Quit Gus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = $0.action == #selector(NSApplication.terminate(_:)) ? nil : self }
        item.menu = menu

        let launcher = Launcher.shared
        launcher.show = { [weak self] in self?.show() }
        launcher.close = { [weak self] in self?.hide() }
        launcher.pasteIntoPrevious = { [weak self] in self?.pasteIntoPrevious() }
        FolderPicker.willPick = { [weak self] in self?.window.level = .normal; self?.window.orderOut(nil) }
        FolderPicker.didPick = { [weak self] in self?.window.level = .modalPanel; self?.show() }
        Settings.shared.onAppearance = { [weak self] in self?.applyAppearance() }
        applyAppearance()
        appearanceWatch = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.applyAppearance() }
        }
        Settings.shared.reindex()
        Settings.shared.onHotkey = { [weak self] combo in self?.register(combo) }
        register(Settings.shared.hotkey)
        Settings.shared.onNotesHotkey = { [weak self] combo in self?.registerNotes(combo) }
        registerNotes(Settings.shared.notesHotkey)
        Launcher.shared.openNotes = { [weak self] text in self?.openNotes(with: text) }

        AppIndex.shared.refreshIfNeeded()
        Rates.shared.refreshIfStale()
        ClipboardHistory.shared.start()

        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard env["GUS_STAY"] != "1" else { return }
            Task { @MainActor in self?.hide() }
        }

        let args = ProcessInfo.processInfo.arguments
        // First run (or --welcome): the welcome steps, inside the bar.
        if !UserDefaults.standard.bool(forKey: "didOnboard") || args.contains("--welcome") {
            let step = args.firstIndex(of: "--welcome-step").flatMap { args.count > $0 + 1 ? Int(args[$0 + 1]) : nil } ?? 0
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                launcher.startWelcome()
                launcher.welcomeStep = step
                self.show()
            }
        }
        // Test hook: --ask "<question>" [--then "<follow-up>"] runs a conversation in the bar.
        if let i = args.firstIndex(of: "--ask"), args.count > i + 1 {
            let q = args[i + 1]
            let then = args.firstIndex(of: "--then").flatMap { args.count > $0 + 1 ? args[$0 + 1] : nil }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                self.show()
                launcher.query = q
                Assistant.shared.ask(q)
                guard let then else { return }
                while Assistant.shared.thinking { try? await Task.sleep(nanoseconds: 200_000_000) }
                launcher.continueChat()
                launcher.query = then
                launcher.activate()
            }
        } else if let i = args.firstIndex(of: "--query"), args.count > i + 1 {
            let q = args[i + 1]
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                self.show()
                launcher.query = q
                // --return presses Return on the first result once it's there.
                if args.contains("--return") {
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    launcher.activate()
                }
            }
        } else if args.contains("--show") || args.contains("--clipboard") {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                self.show()
                if args.contains("--clipboard") { launcher.toggleClipboard() }
            }
        }
        // Test hook: --think holds the "working it out" state (Gus's thought cloud).
        // Test hook: --remove-reminder <id> deletes a reminder a test made, then quits.
        if let i = args.firstIndex(of: "--remove-reminder"), args.count > i + 1 {
            Assistant.shared.removeReminder(args[i + 1])
            NSApp.terminate(nil)
        }
        // --selftest <report file>: run every feature for real, write the report, quit.
        if let i = args.firstIndex(of: "--selftest"), args.count > i + 1 {
            let report = args[i + 1]
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                await SelfTest.run(report: report)
            }
        }
        if args.contains("--think") {
            Task { @MainActor in try? await Task.sleep(nanoseconds: 1_500_000_000); launcher.working = true }
        }
        if let i = args.firstIndex(of: "--notes") {
            let text = args.count > i + 1 && !args[i + 1].hasPrefix("--") ? args[i + 1] : nil
            Task { @MainActor in try? await Task.sleep(nanoseconds: 300_000_000); self.openNotes(with: text) }
        }
        if args.contains("--settings") {
            Task { @MainActor in try? await Task.sleep(nanoseconds: 300_000_000); self.openSettings() }
        }
    }

    private func register(_ combo: Hotkey.Combo) {
        hotkey = nil
        hotkey = Hotkey(combo) { [weak self] in self?.toggle() }
    }

    /// A menu-bar app has no menus of its own, so ⌘A, ⌘C, ⌘V, ⌘Z and ⌘W had nowhere to go. This main menu
    /// is never shown (Gus stays out of the Dock and menu bar) but carries the standard key equivalents.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let app = NSMenu()
        app.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Gus", action: #selector(closeFront), keyEquivalent: "h").target = self
        app.addItem(withTitle: "Quit Gus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app

        let fileItem = NSMenuItem(); main.addItem(fileItem)
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Close", action: #selector(closeFront), keyEquivalent: "w").target = self
        fileItem.submenu = file

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let plain = edit.addItem(withTitle: "Paste and Match Style", action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "v")
        plain.keyEquivalentModifierMask = [.command, .option, .shift]
        edit.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Find…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f").tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    /// ⌘W and ⌘H: put away whichever Gus window is in front.
    @objc func closeFront() {
        if NSApp.keyWindow is NotesPanel { Notes.shared.hide() } else { hide() }
    }

    private func registerNotes(_ combo: Hotkey.Combo) {
        notesHotkey = nil
        notesHotkey = Hotkey(combo, id: 2) { [weak self] in self?.notesPressed() }
    }

    /// The notes hotkey: with words typed in the bar they move into a new note; otherwise show or hide notes.
    private func notesPressed() {
        let launcher = Launcher.shared
        let typed = launcher.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if window.isVisible, launcher.visible, launcher.mode == .search, !typed.isEmpty {
            openNotes(with: typed)
        } else {
            Notes.shared.toggle()
        }
    }

    private func openNotes(with text: String?) {
        if let text, !text.isEmpty { Launcher.shared.query = "" }
        hide()
        Notes.shared.show(adding: text)
    }

    @objc func openNotesMenu() { Notes.shared.show() }
    @objc func openWelcome() { Launcher.shared.startWelcome(); show() }

    @objc func openBar() { show() }
    @objc func openClipboard() { show(); if Launcher.shared.mode != .clipboard { Launcher.shared.toggleClipboard() } }

    @objc func openSettings() { show(); Launcher.shared.switchTo(.settings) }

    /// Inverted needs the Mac's own appearance, so it's read from the app rather than the window.
    private func applyAppearance() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        window.appearance = Settings.shared.barAppearance(systemIsDark: dark)
    }

    private func pasteIntoPrevious() {
        let target = previousApp
        hide()
        target?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { Pasteboard.pasteIntoFrontApp() }
    }

    func toggle() { window.isVisible && Launcher.shared.visible ? hide() : show() }


    func show() {
        hideWork?.cancel()
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = front }
        // On the screen with the pointer, a quarter of the way down, like Spotlight.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            // On the screen with the pointer, a fifth of the way down, like Spotlight (every look).
            let top = f.maxY - f.height * 0.2 + Self.margin
            window.setFrameTopLeftPoint(NSPoint(x: f.midX - window.frame.width / 2, y: top))
        }
        AppIndex.shared.refreshIfNeeded()
        let after = Settings.shared.freshAfter
        if let hiddenAt, after > 0, Date().timeIntervalSince(hiddenAt) > after, Launcher.shared.mode != .welcome {
            Launcher.shared.reset()
        }
        hiddenAt = nil
        Launcher.shared.opened += 1
        Launcher.shared.visible = true
        otter?.barOpened()
        // The fade is AppKit's, on the window itself: it runs at once, instead of waiting for SwiftUI's next
        // event (which is why the bar used to stay invisible until the first keystroke).
        if !window.isVisible { window.alphaValue = 0 }
        NSApp.activate(ignoringOtherApps: true)
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        window.orderFrontRegardless()
        window.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }

        guard monitors.isEmpty, ProcessInfo.processInfo.environment["GUS_STAY"] != "1" else { return }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] event in
            guard let self, event.window == self.window else { return event }
            let p = CGPoint(x: event.locationInWindow.x, y: self.window.frame.height - event.locationInWindow.y)
            if !BarWindowFrame.card.contains(p) { self.hide(); return nil }
            return event
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { event in
            let down = event.modifierFlags.contains(.command)
            if Launcher.shared.commandDown != down { Launcher.shared.commandDown = down }
            return event
        }) { monitors.append(m) }
        // Welcome: Return goes on, ← back, Esc skips.
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            let launcher = Launcher.shared
            guard launcher.mode == .welcome, event.window === self.window else { return event }
            switch event.keyCode {
            case 36, 76: launcher.welcomeNext(); return nil
            case 123 where launcher.welcomeStep != 1: launcher.welcomeBack(); return nil
            case 124 where launcher.welcomeStep != 1: launcher.welcomeNext(); return nil
            case 53: launcher.finishWelcome(); return nil
            default: return event
            }
        }) { monitors.append(m) }
        // ⌫ on an empty field steps back out of the clipboard, settings or an Apple Intelligence chat. The
        // text field's editor eats Delete before SwiftUI sees it, so this is caught here, at the window.
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            let launcher = Launcher.shared
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard event.keyCode == 51, mods.isEmpty, launcher.mode != .search, launcher.query.isEmpty, !launcher.typingInSettings else { return event }
            if launcher.mode == .chat { launcher.leaveChat() } else { launcher.switchTo(.search) }
            return nil
        }) { monitors.append(m) }
        // The copy key (⌥C by default, set in Settings): read from the key code so ⌥ doesn't turn C into ç.
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            let wanted = Settings.shared.copyModifier.flags
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == 8, mods == wanted, Launcher.shared.mode != .settings {
                Launcher.shared.copyPicked(); return nil
            }
            return event
        }) { monitors.append(m) }
        // ⌘, opens settings while the bar is up.
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "," { self?.openSettings(); return nil }
            return event
        }) { monitors.append(m) }
    }

    func hide() {
        guard window.isVisible else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        Launcher.shared.visible = false
        otter?.barClosed()
        hiddenAt = Date()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !Launcher.shared.visible else { return }
            self.window.orderOut(nil)
            // Kept as it was (query, clipboard view, picked row): opening again picks up where you left off.
            Launcher.shared.commandDown = false
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
}
