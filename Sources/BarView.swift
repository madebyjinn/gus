import SwiftUI
import AppKit

/// The bar: one white field. Results grow out of the same card underneath it.
struct BarShell: View {
    let margin: CGFloat
    @EnvironmentObject var launcher: Launcher
    @EnvironmentObject var settings: Settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var assistant = Assistant.shared

    var body: some View {
        Group {
            if Z.gus {
                // Gus and his speech bubble always sit side by side: the field is there, ready, the moment
                // he appears, like the bar in the other looks.
                let talking = true
                let shift = (BarCard.gusWidth + 10) / 2
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 10) {
                        GusTheme.Figure().frame(width: 96, height: 96)
                        // The bubble opens out of its tail, by Gus's shoulder. It fades on its own short curve:
                        // in a beat after he starts stepping aside, out quickly before he steps back, so it's
                        // never a half-transparent sheet sliding across him. Its size is held while it's away
                        // (see BarCard), so nothing collapses mid-fade.
                        BarCard(showing: talking)
                            .padding(.top, 18)
                            .opacity(talking ? 1 : 0)
                            .animation(reduceMotion ? Z.Motion.reduced
                                       : talking ? .easeOut(duration: 0.24).delay(0.06) : .easeOut(duration: 0.14), value: talking)
                            .scaleEffect(talking ? 1 : 0.94, anchor: UnitPoint(x: 0, y: 0.12))
                            .offset(x: talking ? 0 : -18)
                            .allowsHitTesting(talking)
                    }
                    .offset(x: talking ? 0 : shift)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { BarWindowFrame.card = $0 }
                    .padding(.top, margin)
                    .animation(reduceMotion ? Z.Motion.reduced : .spring(response: 0.5, dampingFraction: 1), value: talking)
                    Spacer(minLength: 0)
                }
            } else {
                VStack(spacing: 0) {
                    BarCard()
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { BarWindowFrame.card = $0 }
                        .padding(.horizontal, margin)
                        .padding(.top, margin)
                    Spacer(minLength: 0)
                }
            }
        }
        .id("\(settings.look.rawValue)-\(settings.accent.rawValue)")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: launcher.visible) { _, showing in
            guard Z.gus else { return }
            GusTheme.barShown(showing)
        }
    }
}

enum BarWindowFrame { nonisolated(unsafe) static var card: CGRect = .zero }

/// Sizes and type for the bar. Solid is flat white on soft grey. Liquid Glass follows Apple's own
/// Spotlight panel: a large continuous corner with rows concentric to it, a magnifier and 22 pt field,
/// 44 pt rows with 28 pt icons, system text styles, and the system fill for the selection.
enum Bar {
    static var radius: CGFloat { Z.gus ? 16 : Z.glass ? 26 : 14 }
    static var inset: CGFloat { Z.glass ? 8 : 6 }
    /// Concentric with the panel: its radius less the inset.
    static var rowRadius: CGFloat { Z.gus ? 10 : Z.glass ? 18 : 8 }
    static var fieldHeight: CGFloat { Z.gus ? 44 : Z.glass ? 58 : 52 }
    static var fieldFont: Font { Z.gus ? .system(size: 16) : Z.glass ? .system(size: 22, weight: .regular) : .system(size: 17) }
    static var fieldPadding: CGFloat { Z.gus ? 16 : Z.glass ? 18 : 20 }
    static var rowHeight: CGFloat { Z.glass ? 44 : 40 }
    static var bigRowHeight: CGFloat { Z.glass ? 66 : 62 }
    static var clipRowHeight: CGFloat { Z.glass ? 48 : 44 }
    static var headerHeight: CGFloat { Z.glass ? 26 : 24 }
    static var icon: CGFloat { Z.glass ? 28 : 22 }
    static var bigIcon: CGFloat { Z.glass ? 34 : 30 }
    static var rowPadding: CGFloat { Z.glass ? 10 : 10 }
    static var title: Font { Z.glass ? .system(size: 15) : .system(size: 13.5) }
    static var bigTitle: Font { Z.glass ? .system(size: 26, weight: .medium).monospacedDigit() : .system(size: 22, weight: .medium).monospacedDigit() }
    static var subtitle: Font { Z.glass ? .system(size: 12) : .system(size: 11) }
    static var header: Font { Z.glass ? .system(size: 12, weight: .semibold) : .system(size: 11, weight: .medium) }
    static var hint: Font { Z.glass ? .system(size: 12) : .system(size: 11.5) }
    static var headerColor: Color { Z.glass ? Z.ink2 : Z.ink3 }
}

struct BarCard: View {
    static let width: CGFloat = 680

    /// The Gus look's bubble: one width from the moment it appears, like the bar in the other looks.
    static let gusWidth: CGFloat = 520
    private var cardWidth: CGFloat { Z.gus ? Self.gusWidth : Self.width }
    private var thinking: Bool { Z.gus && (assistant.thinking || launcher.working) }
    @EnvironmentObject var launcher: Launcher
    @ObservedObject private var assistant = Assistant.shared
    @ObservedObject private var clipboard = ClipboardHistory.shared
    @State private var height: CGFloat = 0
    /// The Gus look hides the bubble when there's nothing to say. While it's away its height is held, and
    /// when it comes back it starts at the right height instead of growing into it.
    var showing = true
    @State private var measured: CGFloat = 0
    private final class Opening { var shown = true; var at = Date.distantPast }
    @State private var opening = Opening()

    /// True for a moment after the bubble reappears: height changes then land at once, not as a glide.
    private func justOpened() -> Bool {
        if showing && !opening.shown { opening.at = Date() }
        opening.shown = showing
        return showing && Date().timeIntervalSince(opening.at) < 0.12
    }

    private func snap(_ value: CGFloat) {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { height = value }
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                if launcher.mode == .welcome {
                    WelcomePane()
                } else {
                    BarField()
                    content
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { new in
                // One quick, critically damped glide for every height change; rows themselves never animate.
                measured = new
                if height == 0 { height = new }
                else if justOpened() { snap(new) }
                else if !showing { return }
                else { withAnimation(Z.gus ? .spring(response: 0.34, dampingFraction: 1) : .spring(duration: 0.22, bounce: 0)) { height = new } }
            }
        }
        .frame(width: cardWidth, height: height > 0 ? height : nil, alignment: .top)
        .clipped()
        .background { if !Z.gus { CardBackground() } }
        .modifier(GusTheme.Dress(thinking: thinking))
        .overlay {
            if !Z.glass && !Z.gus { Z.rect(Bar.radius).strokeBorder(Color.black.opacity(0.07), lineWidth: 1) }
        }
        .animation(Z.gus ? .spring(response: 0.5, dampingFraction: 1) : nil, value: thinking)
        // The float: a wide, very soft shadow, plus a tight one for the edge.
        .shadow(color: .black.opacity(Z.glass || Z.gus ? 0 : 0.07), radius: 28, y: 12)
        .shadow(color: .black.opacity(Z.glass || Z.gus ? 0 : 0.04), radius: 2, y: 1)
        .onChange(of: showing) { _, on in
            if justOpened(), on, measured > 0 { snap(measured) }
        }
        .onChange(of: launcher.hits.count) { settleOtter() }
        .onChange(of: launcher.query) { settleOtter() }
        .onChange(of: assistant.thinking) { settleOtter() }
        .onChange(of: launcher.working) { settleOtter() }
        .overlay(alignment: .bottom) {
            if let notice = launcher.notice {
                Group {
                    if Z.glass {
                        // A glass capsule with label text, like the system's own HUDs.
                        Text(notice).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                            .multilineTextAlignment(.center).lineLimit(2)
                            .padding(.horizontal, 14).padding(.vertical, 6).frame(minHeight: 30).frame(maxWidth: 480)
                            .fixedSize()
                            .glassEffect(.regular, in: Capsule())
                            .offset(y: 42)
                    } else {
                        Text(notice).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                            .multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 10).padding(.vertical, 5).frame(minHeight: 24).frame(maxWidth: 460)
                            .fixedSize(horizontal: true, vertical: false)
                            .background(Z.rect(Z.Radius.md).fill(Color(white: 0.09, opacity: 0.94)))
                            .offset(y: 34)
                    }
                }
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
    }

    private func settleOtter() {
        guard Z.gus else { return }
        let hasResults = launcher.mode == .search && launcher.hits.contains { $0.id != "web" && $0.id != "ask" }
        GusTheme.settle(thinking: assistant.thinking || launcher.working,
                                 hasResults: hasResults || assistant.answer != nil,
                                 empty: launcher.query.isEmpty)
    }

    @ViewBuilder
    private var content: some View {
        if launcher.mode == .settings {
            BarDivider()
            ScrollView {
                SettingsPane(filter: launcher.query)
            }
            .scrollIndicators(.automatic)
            .frame(height: Z.gus ? 400 : Z.glass ? 500 : 470)
        } else if launcher.mode == .chat || assistant.active {
            BarDivider()
            AnswerView()
        } else if launcher.mode == .clipboard {
            BarDivider()
            ClipboardList()
        } else if !launcher.hits.isEmpty {
            BarDivider()
            ResultList()
        }
    }
}

private struct CardBackground: View {
    var body: some View {
        if Z.glass, #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: Z.rect(Bar.radius))
        } else if Z.glass {
            Z.rect(Bar.radius).fill(.regularMaterial)
        } else {
            Z.rect(Bar.radius).fill(Z.surface)
        }
    }
}

// MARK: - The field

private struct BarField: View {
    @EnvironmentObject var launcher: Launcher
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Z.glass ? 12 : 10) {
            if Z.glass, launcher.mode == .search {
                // Spotlight's magnifier leads the field.
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            if launcher.mode != .search {
                Label(launcher.mode == .clipboard ? "Clipboard" : launcher.mode == .chat ? Engine.persona : "Settings",
                      systemImage: launcher.mode == .clipboard ? "doc.on.clipboard" : launcher.mode == .chat ? Settings.shared.engine.symbol : "gearshape")
                    .font(.system(size: Z.glass ? 13 : 12, weight: .medium))
                    .foregroundStyle(Z.onAccent)
                    .padding(.horizontal, Z.glass ? 10 : 8).frame(height: Z.glass ? 26 : 22)
                    .background(Capsule().fill(Z.accent))
                    .lineLimit(1)
                    .fixedSize()
                    .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
            }
            TextField(launcher.mode == .clipboard ? "Search clipboard" : launcher.mode == .settings ? "Search settings"
                      : launcher.mode == .chat ? "Ask a follow-up" : "Search",
                      text: $launcher.query)
                .textFieldStyle(.plain)
                .font(Bar.fieldFont)
                .foregroundStyle(Z.ink)
                .focused($focused)
                .onKeyPress(.downArrow) { launcher.move(1); return .handled }
                .onKeyPress(.upArrow) { launcher.move(-1); return .handled }
                .onKeyPress(.tab) { launcher.tab(); return .handled }
                .onKeyPress(.escape) {
                    // Esc steps out of settings; anywhere else it hides Gus.
                    if launcher.mode == .settings { launcher.switchTo(.search) } else { launcher.close() }
                    return .handled
                }
                .onKeyPress(.delete) {
                    guard launcher.mode != .search, launcher.query.isEmpty else { return .ignored }
                    if launcher.mode == .chat { launcher.leaveChat() } else { launcher.switchTo(.search) }
                    return .handled
                }
                .onKeyPress(phases: .down) { press in
                    if press.modifiers == .command, press.characters.lowercased() == "s" { launcher.toggleSettings(); return .handled }
                    return .ignored
                }
                .onKeyPress(keys: [.return], phases: .down) { press in
                    if press.modifiers.contains(.shift) { launcher.continueChat(); return .handled }
                    launcher.activate(alternate: press.modifiers.contains(.command))
                    return .handled
                }
            // Zest: keys in sight. The one shortcut that isn't obvious sits in the field, like a hint.
            do {
            HStack(spacing: 6) {
                if launcher.mode == .settings {
                    Keycap("esc")
                    Text("Back")
                } else if launcher.mode == .chat {
                    Keycap("⌫")
                    Text("Done")
                } else {
                    Keycap("⇥")
                    Text(launcher.mode == .clipboard ? "Back" : "Clipboard")
                }
            }
            .font(Bar.hint)
            .foregroundStyle(Z.ink3)
            .lineLimit(1)
            .fixedSize()
            .contentShape(Rectangle())
            .onTapGesture { launcher.mode == .settings ? launcher.switchTo(.search) : launcher.toggleClipboard() }
            .animation(Z.Motion.smooth, value: launcher.mode)
            }
        }
        .padding(.horizontal, Bar.fieldPadding)
        .frame(height: Bar.fieldHeight)
        .onAppear { focused = true }
        .onChange(of: launcher.opened) { focused = true }
    }
}

// MARK: - Results

private struct ResultList: View {
    @EnvironmentObject var launcher: Launcher
    var body: some View {
        let hits = launcher.hits
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id(Self.top)
                    ForEach(Array(hits.enumerated()), id: \.element.id) { i, hit in
                        if let title = hit.group.title, i == 0 || hits[i - 1].group != hit.group {
                            Text(title).font(Bar.header).foregroundStyle(Bar.headerColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, Bar.rowPadding + 2).padding(.top, i == 0 ? 2 : 8)
                                .frame(height: Bar.headerHeight, alignment: .bottom)
                                .padding(.bottom, Z.glass ? 2 : 0)
                        }
                        HitRow(hit: hit, selected: i == launcher.selection)
                            .id(hit.id)
                            .onTapGesture { launcher.selection = i; launcher.activate() }
                            .onContinuousHover { phase in
                                if case .active = phase { launcher.pointerOver(i) } else { launcher.pointerLeft(i) }
                            }
                    }
                }
                .padding(Bar.inset)
            }
            .scrollIndicators(.never)
            .frame(height: min(listHeight(hits), Z.gus ? 330 : Z.glass ? 440 : 404))
            .onChange(of: launcher.selection) { _, s in
                // The first row scrolls to the very top, so its group header shows too.
                if s == 0 { proxy.scrollTo(Self.top, anchor: .top); return }
                guard hits.indices.contains(s) else { return }
                proxy.scrollTo(hits[s].id)
            }
            .onChange(of: launcher.scrollTop) { proxy.scrollTo(Self.top, anchor: .top) }
            .onChange(of: hits.first?.id) { if launcher.selection == 0 { proxy.scrollTo(Self.top, anchor: .top) } }
        }
    }

    private static let top = "gus.top"

    private func listHeight(_ hits: [Hit]) -> CGFloat {
        var h: CGFloat = Bar.inset * 2
        for (i, hit) in hits.enumerated() {
            h += hit.big ? Bar.bigRowHeight : Bar.rowHeight
            if hit.group.title != nil, i == 0 || hits[i - 1].group != hit.group { h += Bar.headerHeight + (Z.glass ? 2 : 0) }
        }
        return h
    }
}

private struct HitRow: View {
    let hit: Hit
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            HitIcon(icon: hit.icon, size: hit.big ? Bar.bigIcon : Bar.icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(hit.title)
                    .font(hit.big ? Bar.bigTitle : Bar.title)
                    .foregroundStyle(Z.ink).lineLimit(1)
                    .minimumScaleFactor(hit.big ? 0.6 : 1)
                    .truncationMode(hit.group == .files ? .middle : .tail)
                if let sub = hit.subtitle {
                    Text(sub).font(Bar.subtitle).foregroundStyle(Z.ink2).lineLimit(1)
                        .truncationMode(hit.group == .files ? .middle : .tail)
                }
            }
            .layoutPriority(-1)
            Spacer(minLength: 8)
            if selected, let hint = hit.hint {
                RowKeys(primary: hint, alternate: hit.alternateName, tab: hit.tabName, copies: hit.copyText != nil && hit.group != .files,
                        quietOpen: hit.group == .contacts)
            }
        }
        .padding(.horizontal, Bar.rowPadding)
        .frame(height: hit.big ? Bar.bigRowHeight : Bar.rowHeight)
        .background(Z.rect(Bar.rowRadius).fill(selected ? Z.selected : .clear))
        .animation(Z.Motion.hover, value: selected)
        .contentShape(Rectangle())
    }
}

struct HitIcon: View {
    let icon: Hit.Icon
    var size: CGFloat = 22
    var body: some View {
        switch icon {
        case .app(let path), .file(let path):
            Image(nsImage: IconCache.icon(path)).resizable().interpolation(.high).frame(width: size, height: size)
        case .image(let image):
            Image(nsImage: image).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
        case .symbol(let name):
            if Z.glass {
                // On glass a symbol stands on its own, as in Spotlight: no tile behind it.
                Image(systemName: name).font(.system(size: size * 0.68, weight: .regular)).foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: name).font(.system(size: size * 0.6, weight: .regular)).foregroundStyle(Z.glyph)
                    .frame(width: size, height: size)
                    .background(Z.rect(size * 0.26).fill(Z.tile))
            }
        }
    }
}

/// App and file icons, looked up once.
@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]
    static func icon(_ path: String) -> NSImage {
        if let hit = cache[path] { return hit }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 32, height: 32)
        if cache.count > 400 { cache.removeAll() }
        cache[path] = image
        return image
    }
}

/// Zest's keycap chip: a small sunken cap with the glyph in ink-2, a hair darker at the bottom edge.
struct Keycap: View {
    let glyph: String
    init(_ glyph: String) { self.glyph = glyph }
    var body: some View {
        if Z.glass {
            // Apple's own key hint: the glyph in a quiet rounded fill, system type, no bevel.
            Text(glyph)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 6)
                .frame(minWidth: 22, minHeight: 20)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary))
        } else {
            Text(glyph)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Z.ink2)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(Z.rect(5).fill(Z.sunken))
                .overlay(alignment: .bottom) { Z.rect(5).fill(Z.hairlineStrong).frame(height: 1).padding(.horizontal, 2) }
        }
    }
}

/// What Return does on the picked row: the verb, then its keycap. Holding ⌘ swaps in the other action.
private struct RowKeys: View {
    @EnvironmentObject var launcher: Launcher
    let primary: String
    let alternate: String?
    var tab: String? = nil
    var copies = false
    /// Contacts: leave "Open ↩" off, so Copy and Call have room. Return still opens.
    var quietOpen = false
    var body: some View {
        let alt = launcher.commandDown && alternate != nil
        // Return opens: that goes without saying. On a contact the "Open ↩" pair is left off to give
        // Copy and Call room. ⌘ still shows the other action.
        let quietOpen = self.quietOpen && !alt && primary == "Open" && (copies || tab != nil)
        HStack(spacing: 6) {
            if copies && !alt && primary != "Copy" {
                Text("Copy")
                Keycap(Settings.shared.copyModifier.rawValue).padding(.trailing, 6)
            }
            if let tab, !alt {
                Text(tab)
                Keycap("⇥").padding(.trailing, quietOpen ? 0 : 6)
            }
            if !quietOpen {
                Text(alt ? alternate! : primary)
                    .contentTransition(.opacity)
                if alt { Keycap("⌘") }
                Keycap("↩")
            }
        }
        .font(Bar.hint)
        .foregroundStyle(Z.ink2)
        .lineLimit(1)
        .fixedSize()
        .animation(Z.Motion.hover, value: alt)
        .transition(.opacity)
    }
}

// MARK: - Clipboard

private struct ClipboardList: View {
    @EnvironmentObject var launcher: Launcher
    @ObservedObject private var history = ClipboardHistory.shared

    var body: some View {
        let clips = launcher.clipboardShown
        Group {
            if clips.isEmpty {
                VStack(spacing: 4) {
                    if Z.glass {
                        Image(systemName: "doc.on.clipboard").font(.system(size: 24, weight: .light)).foregroundStyle(.tertiary)
                            .padding(.bottom, 4)
                    }
                    Text(history.clips.isEmpty ? "Nothing copied yet" : "Nothing like that")
                        .font(Z.glass ? .headline : .system(size: 13)).foregroundStyle(Z.glass ? Z.ink : Z.ink2)
                    if history.clips.isEmpty {
                        Text("Copy something and it shows up here").font(Bar.subtitle).foregroundStyle(Z.glass ? Z.ink2 : Z.ink3)
                    }
                }
                .frame(maxWidth: .infinity).frame(height: Z.glass ? 120 : 84)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            Color.clear.frame(height: 0).id("gus.clips.top")
                            ForEach(Array(clips.enumerated()), id: \.element.id) { i, clip in
                                ClipRow(clip: clip, selected: i == launcher.selection)
                                    .id(clip.id)
                                    .onTapGesture { launcher.selection = i; launcher.activate() }
                                    .onContinuousHover { phase in
                                        if case .active = phase { launcher.pointerOver(i) } else { launcher.pointerLeft(i) }
                                    }
                                    .contextMenu {
                                        Button("Copy") { launcher.selection = i; launcher.activate() }
                                        Button("Delete") { ClipboardHistory.shared.delete(clip) }
                                    }
                            }
                        }
                        .padding(Bar.inset)
                    }
                    .scrollIndicators(.never)
                    .frame(height: min(CGFloat(clips.count) * Bar.clipRowHeight + Bar.inset * 2, Z.glass ? 440 : 404))
                    .onChange(of: launcher.selection) { _, s in
                        if s == 0 { proxy.scrollTo("gus.clips.top", anchor: .top); return }
                        guard clips.indices.contains(s) else { return }
                        proxy.scrollTo(clips[s].id)
                    }
                    .onChange(of: launcher.scrollTop) { proxy.scrollTo("gus.clips.top", anchor: .top) }
                }
            }
        }
    }
}

private struct ClipRow: View {
    let clip: ClipboardHistory.Clip
    let selected: Bool
    var body: some View {
        HStack(spacing: 12) {
            Group {
                if clip.kind == .image, let image = ClipboardHistory.shared.image(for: clip) {
                    Image(nsImage: image).resizable().scaledToFill().frame(width: Bar.icon + 2, height: Bar.icon + 2).clipShape(Z.rect(6))
                } else if clip.kind == .file {
                    Image(nsImage: IconCache.icon(clip.text)).resizable().frame(width: Bar.icon, height: Bar.icon)
                } else {
                    HitIcon(icon: .symbol(clip.kind == .link ? "link" : "text.alignleft"), size: Bar.icon)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(clip.kind == .file ? (clip.text as NSString).lastPathComponent : clip.text.replacingOccurrences(of: "\n", with: " "))
                    .font(Bar.title).foregroundStyle(Z.ink).lineLimit(1)
                    .truncationMode(clip.kind == .file ? .middle : .tail)
                Text([clip.app, clip.date.formatted(.relative(presentation: .named))].compactMap { $0 }.joined(separator: " · "))
                    .font(Bar.subtitle).foregroundStyle(Z.ink2).lineLimit(1)
            }
            Spacer(minLength: 8)
            if selected {
                RowKeys(primary: (UserDefaults.standard.object(forKey: "pasteDirectly") as? Bool ?? true) ? "Paste" : "Copy",
                        alternate: nil, copies: true)
            }
        }
        .padding(.horizontal, Bar.rowPadding)
        .frame(height: Bar.clipRowHeight)
        .background(Z.rect(Bar.rowRadius).fill(selected ? Z.selected : .clear))
        .animation(Z.Motion.hover, value: selected)
        .contentShape(Rectangle())
    }
}

// MARK: - Apple Intelligence answer

private struct AnswerView: View {
    @EnvironmentObject var launcher: Launcher
    @ObservedObject private var assistant = Assistant.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(assistant.turns) { turn in
                            VStack(alignment: .leading, spacing: 6) {
                                if assistant.turns.count > 1 || launcher.mode == .chat {
                                    Text(turn.question).font(Z.glass ? .system(size: 13, weight: .semibold) : .system(size: 12, weight: .medium)).foregroundStyle(Z.ink2)
                                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                                }
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: Settings.shared.engine.symbol).font(.system(size: Z.glass ? 16 : 14)).foregroundStyle(Z.accent)
                                        .frame(width: 20, height: 20)
                                    if let answer = turn.answer {
                                        Text(answer).font(Bar.title).foregroundStyle(Z.ink)
                                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                    } else {
                                        HStack(spacing: 8) {
                                            ProgressView().controlSize(.small)
                                            Text("Thinking…").font(.system(size: 13.5)).foregroundStyle(Z.ink2)
                                        }
                                    }
                                }
                            }
                            .id(turn.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 340)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: assistant.turns.count) { _, _ in
                    if let last = assistant.turns.last { withAnimation(Z.Motion.smooth) { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            if assistant.answer != nil {
                HStack(spacing: 6) {
                    if launcher.mode == .search {
                        Text("Continue"); Keycap("⇧"); Keycap("↩").padding(.trailing, 8)
                        Text("Copy"); Keycap("↩")
                    } else {
                        Text("Send"); Keycap("↩").padding(.trailing, 8)
                        Text("Copy"); Keycap(Settings.shared.copyModifier.rawValue)
                    }
                }
                .font(Bar.hint).foregroundStyle(Z.ink2)
                .lineLimit(1).fixedSize()
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(Z.glass ? 18 : 16)
    }
}

/// Solid: a one-pixel hairline. Glass: the system divider, as is.
private struct BarDivider: View {
    var body: some View {
        if Z.glass { Divider() } else { Divider().overlay(Z.hairline) }
    }
}
