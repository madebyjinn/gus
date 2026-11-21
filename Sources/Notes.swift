import AppKit
import SwiftUI

/// Floating notes: a small window that stays above everything, on every Space. Plain text, saved as you
/// type (Application Support/Gus/notes.json), a handful of notes you flip through. Its own hotkey
/// (⌃⌥N by default) shows and hides it; text typed in the bar moves into a new note.
@MainActor
final class Notes: ObservableObject {
    static let shared = Notes()

    struct Note: Codable, Identifiable, Equatable { var id = UUID(); var text = ""; var updated = Date() }

    @Published var notes: [Note] = []
    @Published var index = 0
    private var saveWork: DispatchWorkItem?
    private var window: NSPanel?

    private let file: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Gus")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notes.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([Note].self, from: data), !saved.isEmpty {
            notes = saved
        } else {
            notes = [Note()]
        }
    }

    var current: Binding<String> {
        Binding(get: { self.notes.indices.contains(self.index) ? self.notes[self.index].text : "" },
                set: { new in
                    guard self.notes.indices.contains(self.index), self.notes[self.index].text != new else { return }
                    self.notes[self.index].text = new
                    self.notes[self.index].updated = Date()
                    self.save()
                })
    }

    // MARK: Notes

    func new(with text: String = "") {
        // Reuse an empty note at hand instead of piling up blanks.
        if notes.indices.contains(index), notes[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes[index].text = text
        } else {
            notes.insert(Note(text: text), at: 0)
            index = 0
        }
        save()
    }

    func deleteCurrent() {
        guard notes.indices.contains(index) else { return }
        notes.remove(at: index)
        if notes.isEmpty { notes = [Note()] }
        index = min(index, notes.count - 1)
        save()
    }

    func step(_ d: Int) {
        guard !notes.isEmpty else { return }
        withAnimation(Z.Motion.smooth) { index = (index + d + notes.count) % notes.count }
    }

    private func save() {
        saveWork?.cancel()
        let snapshot = notes.filter { !$0.text.isEmpty || $0.id == notes.first?.id }
        let url = file
        let work = DispatchWorkItem {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    // MARK: Window

    var isOpen: Bool { window?.isVisible == true }

    func toggle() { isOpen ? hide() : show() }

    func show(adding text: String? = nil) {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { new(with: text) }
        let panel = window ?? make()
        window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel = window, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    private func make() -> NSPanel {
        let panel = NotesPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 300),
                               styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                               backing: .buffered, defer: false)
        // Clear, so the Liquid Glass look is real glass over what's behind (Solid paints its own paper).
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 240, height: 160)
        panel.contentView = NSHostingView(rootView: NotesView().environmentObject(self).environmentObject(Settings.shared))
        if !panel.setFrameUsingName("GusNotes") {
            if let f = NSScreen.main?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: f.maxX - 340, y: f.maxY - 330))
            }
        }
        panel.setFrameAutosaveName("GusNotes")
        return panel
    }
}

final class NotesPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { Task { @MainActor in Notes.shared.hide() } }
}

private struct NotesView: View {
    @EnvironmentObject var notes: Notes
    @EnvironmentObject var settings: Settings
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Spacer().frame(width: 52)   // room for the close button
                Text(notes.notes.count > 1 ? "Note \(notes.index + 1) of \(notes.notes.count)" : "Note")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Z.ink3)
                    .contentTransition(.numericText())
                Spacer()
                if notes.notes.count > 1 {
                    ZIconButton(symbol: "chevron.left", help: "Previous note (⌘[)") { notes.step(-1) }
                    ZIconButton(symbol: "chevron.right", help: "Next note (⌘])") { notes.step(1) }
                }
                ZIconButton(symbol: "square.and.pencil", help: "New note (⌘N)") { notes.new(); focused = true }
                ZIconButton(symbol: "trash", help: "Delete note") { notes.deleteCurrent() }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)

            TextEditor(text: notes.current)
                .font(.system(size: 14))
                .foregroundStyle(Z.ink)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .focused($focused)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .id(notes.index)
                .transition(.opacity)
                .overlay(alignment: .topLeading) {
                    if notes.current.wrappedValue.isEmpty {
                        Text("Jot something down").font(.system(size: 14)).foregroundStyle(Z.ink3)
                            .padding(.leading, 17).allowsHitTesting(false)
                    }
                }
        }
        // The header shares the title bar's row with the close button, so the note starts right under it.
        .ignoresSafeArea(.container, edges: .top)
        .background {
            if Z.glass {
                Color.clear.glassEffect(.regular, in: Rectangle()).ignoresSafeArea()
            } else {
                Z.paper.ignoresSafeArea()
            }
        }
        .background {
            // Keyboard: ⌘N new, ⌘[ / ⌘] flip.
            Group {
                Button("") { notes.new(); focused = true }.keyboardShortcut("n")
                Button("") { notes.step(-1) }.keyboardShortcut("[")
                Button("") { notes.step(1) }.keyboardShortcut("]")
            }
            .hidden()
        }
        .id("\(settings.look.rawValue)-\(settings.accent.rawValue)")
        .onAppear { focused = true }
    }
}
