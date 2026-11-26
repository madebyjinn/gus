import SwiftUI
import AppKit

// MARK: - Zest design tokens
//
// Zest's structure (tokens, springs, shared components) in a quiet, flat look: grey chrome, white cards with a 1 px #ECECEC rim and full-width
// dividers, 26 pt grey icon tiles beside a 13 pt title and an 11 pt grey line, uppercase section labels,
// small capsule buttons with a rim, black toggles, no brand colour, plain system type.

enum Z {
    static func platform(_ light: UInt32, _ dark: UInt32, _ la: CGFloat = 1, _ da: CGFloat = 1) -> NSColor {
        func make(_ v: UInt32, _ a: CGFloat) -> NSColor {
            NSColor(red: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255,
                    blue: CGFloat(v & 0xFF) / 255, alpha: a)
        }
        return NSColor(name: nil) { ap in
            ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? make(dark, da) : make(light, la)
        }
    }

    private static func dyn(_ light: UInt32, _ dark: UInt32, _ la: CGFloat = 1, _ da: CGFloat = 1) -> Color {
        Color(nsColor: platform(light, dark, la, da))
    }

    /// Liquid Glass look: Apple's own glass, controls and semantic colours, as a native menu-bar app.
    nonisolated(unsafe) static var glass = false

    private static func ns(_ c: NSColor) -> Color { Color(nsColor: c) }

    // Light values are sampled from Search; dark ones follow its dark web theme (#171717 / #1F1F1F / #262626).
    private static let solidPaper = dyn(0xF7F7F7, 0x171717)
    private static let solidSurface = dyn(0xFFFFFF, 0x1F1F1F)

    /// The Gus look: Solid, with Gus. Same calm colours and type; the otter and his speech bubble are
    /// the one quirky thing.
    nonisolated(unsafe) static var gus = false

    // In Glass every token is an AppKit semantic colour, so text and fills vibrate on the glass exactly
    // as they do in Apple's own menus and Control Center.
    static var paper: Color { glass ? .clear : solidPaper }                  // chrome
    static var surface: Color { glass ? ns(.quaternarySystemFill) : solidSurface }   // cards, fields
    static var tile: Color { glass ? ns(.quaternarySystemFill) : dyn(0xF2F2F2, 0x2A2A2A) }
    static var sunken: Color { glass ? ns(.quaternarySystemFill) : dyn(0xEFEFEF, 0x262626) }
    static var selected: Color { glass ? ns(.tertiarySystemFill) : dyn(0xEBEBEB, 0x2C2C2C) }
    static var rowHover: Color { glass ? ns(.quaternarySystemFill) : dyn(0xF7F7F7, 0x252525) }
    static var hairline: Color { glass ? ns(.separatorColor) : dyn(0xECECEC, 0x2C2C2C) }
    static var hairlineStrong: Color { glass ? ns(.separatorColor) : dyn(0xE0E0E0, 0x383838) }
    static var ink: Color { glass ? ns(.labelColor) : dyn(0x1E1E1E, 0xECECEC) }
    static var ink2: Color { glass ? ns(.secondaryLabelColor) : dyn(0x8A8A8A, 0x8E8E8E) }
    static var ink3: Color { glass ? ns(.tertiaryLabelColor) : dyn(0xB0B0B0, 0x5C5C5C) }
    static var glyph: Color { glass ? ns(.secondaryLabelColor) : dyn(0x616161, 0xA8A8A8) }  // line icons
    static let hover = dyn(0x000000, 0xFFFFFF, 0.045, 0.06)
    static let pressed = dyn(0x000000, 0xFFFFFF, 0.08, 0.10)
    static var toggleOff: Color { glass ? dyn(0x000000, 0xFFFFFF, 0.10, 0.16) : dyn(0xE3E3E3, 0x3A3A3A) }
    static let success = dyn(0x1E1E1E, 0xECECEC)
    static let danger = dyn(0xE5484D, 0xFF6B6B)

    // The app accent: primary buttons, switches when on, the selected segment's glass tint.
    nonisolated(unsafe) static var accentChoice = ZAccent(rawValue: UserDefaults.standard.string(forKey: ZAccent.key) ?? "") ?? .clementine
    static var accent: Color { accentChoice == .graphite ? ink : accentChoice.color }
    /// Text on an accent fill: ink on the fruit (white on orange is 2.6:1), white on Graphite.
    static var onAccent: Color {
        accentChoice == .graphite ? dyn(0xFFFFFF, 0x171717) : Color(red: 0.102, green: 0.102, blue: 0.094)
    }

    /// The fruit bowl plus Graphite (ink), as in Dodo.
    enum Fruit {
        static let clementine = Color(red: 1.0, green: 0.478, blue: 0.102)   // #FF7A1A
        static let lemon = Color(red: 0.949, green: 0.761, blue: 0.0)        // #F2C200
        static let lime = Color(red: 0.490, green: 0.749, blue: 0.180)       // #7DBF2E
        static let mint = Color(red: 0.122, green: 0.722, blue: 0.604)       // #1FB89A
        static let blueberry = Color(red: 0.298, green: 0.553, blue: 0.965)  // #4C8DF6
        static let plum = Color(red: 0.663, green: 0.439, blue: 0.941)       // #A970F0
        static let berry = Color(red: 0.925, green: 0.361, blue: 0.541)      // #EC5C8A
    }

    enum Radius { static let sm: CGFloat = 6, md: CGFloat = 7, lg: CGFloat = 10 }
    enum Space { static let xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12, lg: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 40 }

    static func rect(_ radius: CGFloat) -> RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    enum Font {
        static let title = SwiftUI.Font.system(size: 17, weight: .semibold)        // page title
        static let heading = SwiftUI.Font.system(size: 13, weight: .semibold)      // window / pane title
        static let body = SwiftUI.Font.system(size: 13)                            // row titles
        static let bodyStrong = SwiftUI.Font.system(size: 13, weight: .medium)
        static let caption = SwiftUI.Font.system(size: 11)                         // row second lines
        static let button = SwiftUI.Font.system(size: 12)
        static let section = SwiftUI.Font.system(size: 10.5, weight: .semibold)    // UPPERCASE labels
        static let mono = SwiftUI.Font.system(size: 11, weight: .medium).monospacedDigit()
        /// The one big number: a one-time code.
        static let code = SwiftUI.Font.system(size: 17, weight: .medium).monospacedDigit()
    }

    enum Motion {
        /// Every layout change (panes, folding, filtering, the menu's own height): critically damped, so
        /// it glides and never wobbles. Height, contents and fades all share it so they stay in step.
        static let smooth = Animation.spring(duration: 0.34, bounce: 0)
        static let open = Animation.spring(duration: 0.26, bounce: 0.12)
        static let close = Animation.easeIn(duration: 0.14)
        static let hover = Animation.easeOut(duration: 0.12)
        static let press = Animation.spring(response: 0.20, dampingFraction: 0.85)
        static let snap = Animation.spring(response: 0.28, dampingFraction: 0.75)
        static let pop = Animation.spring(response: 0.40, dampingFraction: 0.62)
        static let settle = Animation.spring(response: 0.55, dampingFraction: 0.90)
        static let reduced = Animation.easeInOut(duration: 0.12)
    }
}

enum ZAccent: String, CaseIterable, Identifiable {
    case clementine = "Clementine", lemon = "Lemon", lime = "Lime", mint = "Mint",
         blueberry = "Blueberry", plum = "Plum", berry = "Berry", graphite = "Graphite"
    static let key = "accent"
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .clementine: return Z.Fruit.clementine
        case .lemon: return Z.Fruit.lemon
        case .lime: return Z.Fruit.lime
        case .mint: return Z.Fruit.mint
        case .blueberry: return Z.Fruit.blueberry
        case .plum: return Z.Fruit.plum
        case .berry: return Z.Fruit.berry
        case .graphite: return Color(red: 0.42, green: 0.42, blue: 0.42)
        }
    }
}

/// Set while views are drawn offline (ImageRenderer can't draw text fields).
enum ZRenderHint { nonisolated(unsafe) static var offline = false }

// MARK: - Surfaces

extension View {
    /// The floating shadow: wide and very soft.
    func zFloatShadow() -> some View {
        shadow(color: .black.opacity(0.08), radius: 14, y: 4)
    }

    /// A white card with a 1 px rim.
    /// Solid: a white card with a 1 px rim. Glass: a grouped section in the system fill, no rim, as in
    /// Apple's own glass panels (no glass stacked on glass).
    func zCard(_ radius: CGFloat = Z.Radius.lg) -> some View {
        background(Z.rect(radius).fill(Z.surface))
            .overlay(Z.rect(radius).strokeBorder(Z.glass ? .clear : Z.hairline, lineWidth: 1))
            .clipShape(Z.rect(radius))
    }

    /// Folds content open and shut inside the layout: its height animates from zero, so the card
    /// around it grows and shrinks with it (an if-insertion would hold its space until the end).
    func zReveal(_ open: Bool) -> some View {
        fixedSize(horizontal: false, vertical: true)
            .frame(height: open ? nil : 0, alignment: .top)
            .clipped()
            .opacity(open ? 1 : 0)
            .allowsHitTesting(open)
            .accessibilityHidden(!open)
    }

    func zAnimation<V: Equatable>(_ animation: Animation, value: V, reduce: Bool) -> some View {
        self.animation(reduce ? Z.Motion.reduced : animation, value: value)
    }
}

/// A card of rows with full-width dividers between them.
struct ZCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    if i > 0 { ZDivider() }
                    row
                }
            }
        }
        .zCard()
    }
}

struct ZDivider: View {
    var body: some View {
        if Z.glass { Divider().padding(.leading, 10) } else { Rectangle().fill(Z.hairline).frame(height: 1) }
    }
}

/// Section label: a small glyph and UPPERCASE grey text above a card.
struct ZSection<Content: View>: View {
    let title: String
    var symbol: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        if Z.glass {
            // HIG grouped form: a sentence-case headline over a grouped box, footnote below.
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline).foregroundStyle(.primary).padding(.leading, 4)
                ZCard { content }
                if let footer {
                    Text(footer).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    if let symbol { Image(systemName: symbol).font(.system(size: 9.5, weight: .medium)) }
                    Text(title.uppercased()).font(Z.Font.section).tracking(0.5)
                }
                .foregroundStyle(Z.ink2)
                .padding(.leading, 2)
                ZCard { content }
                if let footer {
                    Text(footer).font(Z.Font.caption).foregroundStyle(Z.ink2)
                        .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
                }
            }
        }
    }
}

/// The 26 pt grey tile that leads every row: a line glyph or a letter.
struct ZTile: View {
    var symbol: String? = nil
    var letter: String? = nil
    var size: CGFloat = 26
    var body: some View {
        Group {
            if let symbol {
                Image(systemName: symbol).font(.system(size: size * 0.46, weight: .regular))
            } else {
                Text(letter ?? "").font(.system(size: size * 0.44, weight: .medium))
            }
        }
        .foregroundStyle(Z.glyph)
        .frame(width: size, height: size)
        .background(Z.rect(Z.Radius.sm).fill(Z.tile))
    }
}

/// A settings row: tile, 13 pt title, 11 pt grey line, and whatever goes on the right.
struct ZRow<Trailing: View>: View {
    var symbol: String? = nil
    let title: String
    var subtitle: String? = nil
    var dimmed = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        if Z.glass {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body).foregroundStyle(dimmed ? .tertiary : .primary)
                        .lineLimit(1).truncationMode(.middle)
                    if let subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(dimmed ? .tertiary : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Z.Space.sm)
                trailing.fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minHeight: subtitle == nil ? 32 : 42)
        } else {
            zest
        }
    }

    private var zest: some View {
        HStack(spacing: Z.Space.md) {
            if let symbol { ZTile(symbol: symbol) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Z.Font.body).foregroundStyle(dimmed ? Z.ink3 : Z.ink)
                    .lineLimit(1).truncationMode(.middle)
                if let subtitle {
                    Text(subtitle).font(Z.Font.caption).foregroundStyle(dimmed ? Z.ink3 : Z.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Z.Space.sm)
            trailing.fixedSize()
        }
        .padding(.horizontal, Z.Space.md)
        .padding(.vertical, subtitle == nil ? 9 : 9)
        .frame(minHeight: subtitle == nil ? 40 : 50)
    }
}

// MARK: - Controls

/// Buttons. Secondary: a small white capsule with a rim ("Open", "Rename…"). Filled: grey capsule
/// ("Set up"). Primary: black capsule. Danger: rim with red text. Quiet: text only.
struct ZButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, filled, quiet, danger }
    var kind: Kind = .secondary
    var large = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule()
        let pressed = configuration.isPressed
        configuration.label
            .font(large ? Z.Font.bodyStrong : Z.Font.button)
            .foregroundStyle(kind == .primary ? Z.onAccent : kind == .danger ? Z.danger
                             : kind == .filled || kind == .quiet ? Z.ink2 : Z.ink)
            .padding(.horizontal, kind == .quiet ? 6 : large ? 16 : 10)
            .frame(height: large ? 30 : 22)
            .background {
                switch kind {
                case .primary: shape.fill(Z.accent.opacity(pressed ? 0.8 : 1))
                case .filled: shape.fill(pressed ? Z.selected : Z.sunken)
                case .quiet: shape.fill(pressed ? Z.pressed : .clear)
                case .secondary, .danger:
                    shape.fill(pressed ? Z.rowHover : Z.surface)
                        .overlay(shape.strokeBorder(Z.hairlineStrong, lineWidth: 1))
                }
            }
            .contentShape(shape)
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.45)
            .zAnimation(Z.Motion.press, value: pressed, reduce: reduceMotion)
    }
}

/// A bare grey line glyph, for footers and toolbars.
struct ZIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        if Z.glass, #available(macOS 26.0, *) {
            Button(action: action) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .help(help)
            .accessibilityLabel(help)
        } else {
            zest
        }
    }

    private var zest: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(hovering ? Z.ink : Z.glyph)
                .frame(width: 24, height: 24)
                .background(Z.rect(Z.Radius.sm).fill(hovering ? Z.hover : .clear))
                .contentShape(Z.rect(Z.Radius.sm))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The switch: 30 × 18, black with a white knob when on, light grey when off. Bare by default.
struct ZToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? Z.accent : Z.toggleOff)
                Circle().fill(configuration.isOn && Z.accentChoice == .graphite ? Z.onAccent : Color.white)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
                    .frame(width: 14, height: 14).padding(2)
            }
            .frame(width: 30, height: 18)
            .opacity(enabled ? 1 : 0.45)
            .zAnimation(Z.Motion.press, value: configuration.isOn, reduce: reduceMotion)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("toggle"))
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

extension View {
    /// Buttons: Zest's capsules in Solid; in Glass, Apple's glass button styles (glassProminent tinted
    /// with the accent for the one primary, glass for the rest, borderless for quiet).
    @ViewBuilder
    func zButton(_ kind: ZButtonStyle.Kind = .secondary, large: Bool = false) -> some View {
        if Z.glass, #available(macOS 26.0, *) {
            switch kind {
            case .primary: buttonStyle(.glassProminent).tint(Z.accent).controlSize(large ? .regular : .small)
            case .danger: buttonStyle(.glass).foregroundStyle(.red).controlSize(.small)
            case .quiet: buttonStyle(.borderless).controlSize(.small)
            case .secondary, .filled: buttonStyle(.glass).controlSize(.small)
            }
        } else {
            buttonStyle(ZButtonStyle(kind: kind, large: large))
        }
    }

    /// Switches: Zest's in Solid; Apple's own mini switch, tinted with the accent, in Glass.
    @ViewBuilder
    func zToggle() -> some View {
        if Z.glass {
            toggleStyle(.switch).controlSize(.mini).tint(Z.accent).labelsHidden()
        } else {
            toggleStyle(ZToggleStyle()).labelsHidden()
        }
    }
}

/// Segmented choice: grey track, white thumb (Apple's segmented control in Glass).
struct ZSegmented<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String
    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if Z.glass {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { Text(label($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.regular)
            .fixedSize()
        } else {
            zest
        }
    }

    private var zest: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    withAnimation(reduceMotion ? Z.Motion.reduced : Z.Motion.snap) { selection = option }
                } label: {
                    Text(label(option))
                        .font(Z.Font.button)
                        .foregroundStyle(on ? Z.ink : Z.ink2)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                        .background {
                            if on {
                                Z.rect(Z.Radius.sm - 1).fill(Z.surface)
                                    .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(option))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Z.rect(Z.Radius.md).fill(Z.sunken))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// A small text field: white, 1 px rim, grey glyph, optional key hint on the right.
struct ZField: View {
    let placeholder: String
    @Binding var text: String
    var symbol: String? = nil
    var hint: String? = nil
    var mono = false
    @FocusState private var focused: Bool

    var body: some View {
        if Z.glass && !ZRenderHint.offline {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(mono ? .body.monospaced() : .body)
        } else {
            zest
        }
    }

    private var zest: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(Z.ink2)
            }
            Group {
                if Z.glass && !ZRenderHint.offline {
                    TextField(placeholder, text: $text).textFieldStyle(.plain).focused($focused)
                } else if ZRenderHint.offline {
                    Text(text.isEmpty ? placeholder : text).foregroundStyle(text.isEmpty ? Z.ink3 : Z.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(placeholder, text: $text).textFieldStyle(.plain).focused($focused)
                }
            }
            .font(mono ? .system(size: 12, design: .monospaced) : Z.Font.body)
            .foregroundStyle(Z.ink)
            if let hint, text.isEmpty {
                Text(hint).font(Z.Font.caption).foregroundStyle(Z.ink3)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Z.rect(Z.Radius.md).fill(Z.surface))
        .overlay(Z.rect(Z.Radius.md).strokeBorder(
            Z.glass ? (focused ? Color(nsColor: .keyboardFocusIndicatorColor) : .clear)
                    : (focused ? Z.ink.opacity(0.35) : Z.hairlineStrong),
            lineWidth: Z.glass && focused ? 2 : 1))
    }
}

/// The countdown ring: a thin track with an arc that empties as the code ages.
struct ZRing: View {
    var progress: Double
    var color: Color
    var size: CGFloat = 14
    var body: some View {
        ZStack {
            Circle().stroke(Z.toggleOff, lineWidth: 2)
            Circle().trim(from: 0, to: max(0.001, progress))
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}


// MARK: - Native search field (Glass)

/// AppKit's NSSearchField: the real thing, with its magnifier, clear button and focus ring. Arrow keys,
/// Return and Esc are handed back so the list can be driven from the keyboard.
struct NativeSearchField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var focusToken: Int
    var onSubmit: () -> Void
    var onMove: (Int) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.focusRingType = .default
        field.controlSize = .regular
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.focused != focusToken {
            context.coordinator.focused = focusToken
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearchField
        var focused = -1
        init(parent: NativeSearchField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1); return true
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1); return true
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit(); return true
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel(); return true
            default: return false
            }
        }
    }
}
