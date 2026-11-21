import AppKit
import Carbon.HIToolbox

/// A global shortcut through Carbon: no Accessibility or Input Monitoring permission needed.
final class Hotkey {
    private var ref: EventHotKeyRef?
    private static var handler: EventHandlerRef?
    private static var actions: [UInt32: () -> Void] = [:]
    private let id: UInt32

    struct Combo: Equatable, Codable, Hashable {
        var keyCode: UInt32
        var modifiers: UInt32
        var label: String
        static let optionSpace = Combo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), label: "⌥Space")
        static let controlSpace = Combo(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey), label: "⌃Space")
        static let commandSpace = Combo(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey), label: "⌘Space")
        static let optionCommandSpace = Combo(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | optionKey), label: "⌥⌘Space")
        static let all = [optionSpace, controlSpace, optionCommandSpace, commandSpace]
        static let controlOptionN = Combo(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey), label: "⌃⌥N")
        static let optionShiftN = Combo(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(optionKey | shiftKey), label: "⌥⇧N")
        static let controlOptionCommandN = Combo(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey | cmdKey), label: "⌃⌥⌘N")
        static let notes = [controlOptionN, optionShiftN, controlOptionCommandN]
    }

    init(_ combo: Combo, id: UInt32 = 1, action: @escaping () -> Void) {
        self.id = id
        Hotkey.actions[id] = action
        if Hotkey.handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
                DispatchQueue.main.async { Hotkey.actions[hk.id]?() }
                return noErr
            }, 1, &spec, nil, &Hotkey.handler)
        }
        RegisterEventHotKey(combo.keyCode, combo.modifiers, EventHotKeyID(signature: OSType(0x5045454C), id: id),
                            GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Hotkey.actions[id] = nil
    }
}

@MainActor
enum Pasteboard {
    /// Puts text back on the clipboard. Marked transient so Gus's own history skips it.
    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        ClipboardHistory.shared.ignoreNextChange()
        NotificationCenter.default.post(name: .gusCopied, object: nil)
    }

    /// Types ⌘V into the app in front. Needs Accessibility; quietly does nothing without it.
    static func pasteIntoFrontApp() {
        guard AXIsProcessTrusted() else { return }
        let src = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    static func askForAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}


extension Notification.Name {
    /// Something was copied (by Gus, or anywhere on the Mac): the menu-bar otter winks.
    static let gusCopied = Notification.Name("GusCopied")
}
