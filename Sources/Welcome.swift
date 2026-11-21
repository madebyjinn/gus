import SwiftUI
import AppKit

/// First run, hosted by Gus. Four short beats inside the bar: he says hello and you pick his shortcut,
/// you try him out for real (the answers are live), you pick a look, and he sends you off. Return goes
/// on, Esc skips. No permission prompts here; Gus asks the first time a feature needs one.
struct WelcomePane: View {
    @EnvironmentObject var launcher: Launcher
    @ObservedObject var settings = Settings.shared
    @State private var tried = ProcessInfo.processInfo.environment["GUS_TRY"] ?? ""   // GUS_TRY: test hook
    @State private var didTry = false
    @FocusState private var typing: Bool

    static let steps = 4
    private var step: Int { launcher.welcomeStep }

    private var line: String {
        switch step {
        case 0: return "Hi, I'm Gus. I fetch things."
        case 1: return didTry ? "See? Easy. Try another, or carry on." : "Go on, ask me something."
        case 2: return "How should I look?"
        default: return "That's it. Call me any time."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                // In the Gus look he's already standing beside the bubble.
                if !Z.gus {
                    GusTheme.Figure().frame(width: 84, height: 84).padding(.top, -4)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Typewriter(text: line)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Z.ink)
                        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                    Group {
                        switch step {
                        case 0: hello
                        case 1: tryIt
                        case 2: look
                        default: done
                        }
                    }
                    .id(step)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 14)),
                                            removal: .opacity.combined(with: .offset(x: -14))))
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Rectangle().fill(Z.hairline).frame(height: 1)
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(0..<Self.steps, id: \.self) { i in
                        Capsule().fill(i == step ? Z.accent : Z.toggleOff)
                            .frame(width: i == step ? 16 : 6, height: 6)
                    }
                }
                .animation(Z.Motion.snap, value: step)
                Spacer()
                if step < Self.steps - 1 {
                    Button("Skip") { launcher.finishWelcome() }.zButton(.quiet)
                }
                if step > 0 {
                    Button("Back") { launcher.welcomeBack() }.zButton(.secondary)
                }
                Button(step < Self.steps - 1 ? "Next" : "Start using Gus") { launcher.welcomeNext() }
                    .zButton(.primary)
            }
            .padding(.horizontal, 18)
            .frame(height: 48)
        }
        .onAppear { GusTheme.react(.greet) }
        .onChange(of: step) { _, s in
            switch s {
            case 1: typing = true; GusTheme.react(.say)
            case 2: GusTheme.react(.say)
            case 3: GusTheme.react(.cheer)
            default: GusTheme.react(.greet)
            }
        }
    }

    // MARK: 1. Hello

    private var hello: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Apps, files, sums, money, the weather, your clipboard and notes. One field.")
                .font(.system(size: 13)).foregroundStyle(Z.ink2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                BigKeys(label: settings.hotkey.label)
                Text("calls me from anywhere").font(.system(size: 13)).foregroundStyle(Z.ink2)
            }
            .padding(.top, 2)
            ZSegmented(title: "Shortcut", selection: $settings.hotkey, options: Hotkey.Combo.all) { $0.label }
                .frame(width: Z.glass ? nil : 330)
                .onChange(of: settings.hotkey) { GusTheme.react(.wink) }
            if settings.hotkey == .commandSpace {
                Text("Turn off Spotlight's ⌘Space first: System Settings › Keyboard › Keyboard Shortcuts › Spotlight.")
                    .font(.system(size: 11.5)).foregroundStyle(Z.ink3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 2. Try it (live)

    private static let ideas = ["ten times 12", "5 km in miles", "$20", "15% of 80", "sqrt(144)"]

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Z.ink2)
                TextField("Type a sum, or tap one below", text: $tried)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(Z.ink)
                    .focused($typing)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Z.rect(10).fill(Z.sunken))

            if let answer = Self.answer(tried) {
                HStack(spacing: 12) {
                    HitIcon(icon: .symbol(answer.symbol), size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(answer.title).font(.system(size: 22, weight: .medium).monospacedDigit()).foregroundStyle(Z.ink)
                        Text(answer.subtitle).font(.system(size: 11)).foregroundStyle(Z.ink2)
                    }
                    Spacer()
                    Text("Copy").font(.system(size: 11.5)).foregroundStyle(Z.ink2)
                    Keycap("↩")
                }
                .padding(.horizontal, 12)
                .frame(height: 56)
                .background(Z.rect(10).fill(Z.selected))
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }

            HStack(spacing: 6) {
                ForEach(Self.ideas, id: \.self) { idea in
                    Button(idea) {
                        withAnimation(Z.Motion.smooth) { tried = idea }
                        typing = true
                    }
                    .zButton(.filled)
                }
            }
        }
        .animation(Z.Motion.smooth, value: Self.answer(tried)?.title)
        .onAppear { typing = true }
        .onChange(of: Self.answer(tried)?.title) { _, title in
            guard title != nil else { return }
            if !didTry { didTry = true; GusTheme.react(.cheer) } else { GusTheme.react(.say) }
        }
    }

    struct TryAnswer { let title: String; let subtitle: String; let symbol: String }

    /// The same engines the bar uses, so what you try here is real.
    static func answer(_ text: String) -> TryAnswer? {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        if let money = Currency.parse(q) {
            let to = money.to ?? (money.from == Currency.local ? "USD" : Currency.local)
            Rates.shared.refreshIfStale()
            if let v = Rates.shared.convert(money.amount, from: money.from, to: to) {
                return TryAnswer(title: Currency.format(v, to), subtitle: "\(Currency.format(money.amount, money.from)) in \(to), today's rate",
                                 symbol: "dollarsign.arrow.circlepath")
            }
            return TryAnswer(title: "Getting rates…", subtitle: "\(money.from) to \(to)", symbol: "dollarsign.arrow.circlepath")
        }
        if let v = Calculator.evaluate(q) {
            return TryAnswer(title: Calculator.format(v), subtitle: q, symbol: "equal.circle")
        }
        if let expr = NumberWords.expression(q), let v = Calculator.evaluate(expr) {
            return TryAnswer(title: Calculator.format(v), subtitle: expr, symbol: "equal.circle")
        }
        if let r = Units.parse(q) {
            let d = Units.describe(r)
            return TryAnswer(title: d.title, subtitle: d.subtitle, symbol: "ruler")
        }
        return nil
    }

    // MARK: 3. Look

    private var look: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ForEach(Settings.Look.available, id: \.self) { l in
                    LookCard(look: l, selected: settings.look == l) {
                        withAnimation(Z.Motion.smooth) { settings.look = l }
                        GusTheme.react(.cheer)
                    }
                }
            }
            HStack(spacing: 14) {
                Text("Accent").font(.system(size: 13)).foregroundStyle(Z.ink2)
                AccentDots(selection: $settings.accent)
                Spacer()
                Text("Appearance").font(.system(size: 13)).foregroundStyle(Z.ink2).fixedSize()
                ZSegmented(title: "Appearance", selection: $settings.appearance, options: [.system, .light, .dark]) { $0.rawValue }
                    .frame(width: Z.glass ? nil : 170)
            }
        }
    }

    // MARK: 4. Done

    private var done: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                tip(settings.hotkey.label, "Call me")
                tip("⇥", "Clipboard")
                tip(settings.notesHotkey.label, "Notes")
                tip("⌘S", "Settings")
            }
            VStack(spacing: 0) {
                ZRow(symbol: "power", title: "Open at login", subtitle: "So I'm always around") {
                    Toggle("", isOn: Binding(get: { settings.openAtLogin }, set: { settings.setOpenAtLogin($0) })).zToggle()
                }
                ZDivider()
                ZRow(symbol: "folder", title: "Find files too", subtitle: "Desktop, Documents and Downloads; more in Settings") {
                    Toggle("", isOn: $settings.searchFiles).zToggle()
                }
            }
            .zCard()
            Text("I'll ask for Calendar, Reminders, Contacts or Location the first time you need them, not before.")
                .font(.system(size: 11.5)).foregroundStyle(Z.ink3).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tip(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) { Keycap(key); Text(label).font(.system(size: 12)).foregroundStyle(Z.ink2) }
    }
}

/// Gus's line, typed out a few letters at a time.
private struct Typewriter: View {
    let text: String
    @State private var shown = 0
    @State private var timer: Timer?

    var body: some View {
        Text(String(text.prefix(shown)))
            .onAppear { start() }
            .onChange(of: text) { start() }
            .onDisappear { timer?.invalidate() }
            .accessibilityLabel(text)
    }

    private func start() {
        timer?.invalidate()
        shown = 0
        let full = text.count
        timer = Timer.scheduledTimer(withTimeInterval: 0.022, repeats: true) { t in
            Task { @MainActor in
                if shown >= full { t.invalidate() } else { shown += 1 }
            }
        }
    }
}

/// A look to pick: a little picture of the bar in that look, with its name.
private struct LookCard: View {
    let look: Settings.Look
    let selected: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Z.sunken)
                    preview
                }
                .frame(height: 58)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(selected ? Z.accent : .clear, lineWidth: 2))
                Text(look.rawValue).font(.system(size: 12, weight: selected ? .semibold : .regular)).foregroundStyle(selected ? Z.ink : Z.ink2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var preview: some View {
        switch look {
        case .solid:
            bar(RoundedRectangle(cornerRadius: 5, style: .continuous), fill: Color.white, shadow: 0.12)
        case .glass:
            bar(RoundedRectangle(cornerRadius: 9, style: .continuous), fill: Color.white.opacity(0.45), shadow: 0)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.9), lineWidth: 1).frame(width: 96, height: 22))
        case .gus:
            GusTheme.LookPreview()
        }
    }

    private func bar<S: Shape>(_ shape: S, fill: Color, shadow: Double) -> some View {
        shape.fill(fill).shadow(color: .black.opacity(shadow), radius: 4, y: 2).frame(width: 96, height: 22)
    }
}

/// The shortcut as big keycaps.
private struct BigKeys: View {
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            ForEach(parts(label), id: \.self) { p in
                Text(p)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Z.ink)
                    .padding(.horizontal, p.count > 1 ? 10 : 0)
                    .frame(minWidth: 32, minHeight: 32)
                    .background(Z.rect(7).fill(Z.sunken))
                    .overlay(alignment: .bottom) { Z.rect(7).fill(Z.hairlineStrong).frame(height: 2).padding(.horizontal, 3) }
            }
        }
    }

    private func parts(_ s: String) -> [String] {
        var out: [String] = []
        var rest = Substring(s)
        while let c = rest.first, "⌘⌥⌃⇧".contains(c) { out.append(String(c)); rest = rest.dropFirst() }
        if !rest.isEmpty { out.append(String(rest)) }
        return out
    }
}
