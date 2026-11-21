import SwiftUI
import AppKit
import Combine

/// The Gus look: the bar becomes a speech bubble and Gus stands beside it. His torso is painted art
/// (Resources/Otter, eight poses from one sheet) flipped like a puppet: he blinks, talks when answers
/// land, thinks while something is being worked out, presents your results, and cheers when you copy.
@MainActor
final class OtterActor: ObservableObject {
    static let shared = OtterActor()

    enum Pose: Int, CaseIterable { case idle = 1, blink, talk, happy, think, wink, sleepy, present }
    @Published private(set) var pose: Pose = .idle

    private var rest: Pose = .idle
    private var generation = 0
    private var blinkTimer: Timer?
    private var lastTouch = Date()
    private var watching: [Any] = []

    private static var frames: [Pose: NSImage] = [:]
    static func image(_ pose: Pose) -> NSImage? {
        if let hit = frames[pose] { return hit }
        guard let url = Bundle.main.url(forResource: "otter-\(pose.rawValue)", withExtension: "png", subdirectory: "Otter"),
              let image = NSImage(contentsOf: url) else { return nil }
        frames[pose] = image
        return image
    }

    private init() {
        watching.append(NotificationCenter.default.addObserver(forName: .gusCopied, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cheer() }
        })
    }

    /// Called while the bar is showing in the Gus look.
    func start() {
        guard blinkTimer == nil else { return }
        scheduleBlink()
    }

    func stop() {
        blinkTimer?.invalidate()
        blinkTimer = nil
    }

    /// What he settles into, from what the bar is doing.
    func settle(thinking: Bool, hasResults: Bool, empty: Bool) {
        lastTouch = Date()
        let next: Pose = thinking ? .think : hasResults ? .present : .idle
        guard next != rest else { return }
        let hadResults = rest == .present
        rest = next
        if next == .present && !hadResults { say() } else { play([], then: next) }
    }

    /// A few mouth flaps, then present.
    func say() {
        play([(.talk, 0.0), (.idle, 0.11), (.talk, 0.11), (.idle, 0.11), (.talk, 0.11)], hold: 0.12, then: rest)
    }

    func cheer() {
        play([(.happy, 0.0)], hold: 0.9, then: rest)
    }

    func wink() {
        play([(.wink, 0.0)], hold: 0.7, then: rest)
    }

    func greet() {
        lastTouch = Date()
        rest = .idle
        play([(.happy, 0.0), (.idle, 0.35), (.talk, 0.12), (.idle, 0.12)], hold: 0.05, then: .idle)
    }

    private func scheduleBlink() {
        blinkTimer = Timer.scheduledTimer(withTimeInterval: .random(in: 2.6...5.5), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.pose == .idle {
                    // Left alone for a while with nothing typed: he nods off.
                    if Date().timeIntervalSince(self.lastTouch) > 25 { self.pose = .sleepy }
                    else { self.play([(.blink, 0.0)], hold: 0.12, then: .idle) }
                }
                self.scheduleBlink()
            }
        }
    }

    private func play(_ frames: [(Pose, Double)], hold: Double = 0, then: Pose) {
        generation += 1
        let run = generation
        var at = 0.0
        for (p, delay) in frames {
            at += delay
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in
                guard let self, self.generation == run else { return }
                self.pose = p
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + at + hold) { [weak self] in
            guard let self, self.generation == run else { return }
            self.pose = then
        }
    }
}

/// Gus himself, floating: the painted bust, bobbing gently. Click him for a wink.
struct OtterFigure: View {
    @ObservedObject private var actor = OtterActor.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false
    static let size: CGFloat = 96

    var body: some View {
        Group {
            if let image = OtterActor.image(actor.pose) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit().padding(30)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .transaction { $0.animation = nil }        // pose swaps are cuts, never tweened by a passing spring
        .offset(y: up ? -2.5 : 2)
        .contentShape(Rectangle())
        .onTapGesture { actor.wink() }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) { up = true }
        }
        .accessibilityLabel("Gus")
    }
}

/// A hand-drawn bubble: a rounded box whose outline wanders a little, never quite straight. As `cloud`
/// goes from 0 to 1 the edge puffs out into scallops and it becomes a thought cloud.
struct WobblyBubble: Shape {
    var cloud: CGFloat = 0
    var seed: CGFloat = 0
    /// How far the line wanders (0 = a clean rounded box).
    var wobble: CGFloat = 1
    var radius: CGFloat = 26
    var inset: CGFloat = 9

    var animatableData: CGFloat {
        get { cloud }
        set { cloud = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r0 = rect.insetBy(dx: inset, dy: inset)
        let radius = min(self.radius, r0.height / 2, r0.width / 2)
        let w = r0.width - 2 * radius, h = r0.height - 2 * radius
        let arc = .pi * radius / 2
        let perimeter = 2 * w + 2 * h + 4 * arc
        let steps = max(48, Int(perimeter / 4))
        var path = Path()
        for i in 0...steps {
            let (p, n, d) = point(at: perimeter * CGFloat(i) / CGFloat(steps), r0, radius, w, h, arc)
            let q = CGPoint(x: p.x + n.x * d, y: p.y + n.y * d)
            if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
        }
        path.closeSubpath()
        return path
    }

    /// How far the line strays at a place on one side. Each side is measured from a corner that doesn't
    /// move when the bubble grows (top and bottom from the left, the sides from the top), so the drawn
    /// edge holds still while the bubble resizes instead of crawling along it.
    private func stray(_ side: CGFloat, _ u: CGFloat) -> CGFloat {
        let k = seed + side * 1.9
        // Three lazy waves of different lengths: a long sag, a medium wander and a little tremor.
        let wander = wobble * (2.4 * sin(u / 97 + k) + 1.3 * sin(u / 37 + k * 1.7) + 0.5 * sin(u / 11 + k * 2.9))
        let puff = cloud * 5.5 * abs(sin(.pi * u / 44 + side))
        return wander + puff
    }

    /// The point, outward normal and stray at distance `s` along a rounded rectangle, clockwise from the
    /// top left. Corners blend from one side's stray to the next.
    private func point(at s: CGFloat, _ r: CGRect, _ rad: CGFloat, _ w: CGFloat, _ h: CGFloat, _ arc: CGFloat) -> (CGPoint, CGPoint, CGFloat) {
        var s = s
        func corner(_ c: CGPoint, _ start: CGFloat, _ t: CGFloat, _ from: CGFloat, _ to: CGFloat) -> (CGPoint, CGPoint, CGFloat) {
            let a = start + t * .pi / 2
            let n = CGPoint(x: cos(a), y: sin(a))
            let ease = t * t * (3 - 2 * t)
            return (CGPoint(x: c.x + rad * n.x, y: c.y + rad * n.y), n, from + (to - from) * ease)
        }
        // Stray at each side's two ends, for the corners to blend between.
        let topEnd = stray(0, w), rightStart = stray(1, 0), rightEnd = stray(1, h)
        let bottomRight = stray(2, w), bottomLeft = stray(2, 0), leftBottom = stray(3, h), leftTop = stray(3, 0), topStart = stray(0, 0)

        if s < w { return (CGPoint(x: r.minX + rad + s, y: r.minY), CGPoint(x: 0, y: -1), stray(0, s)) }
        s -= w
        if s < arc { return corner(CGPoint(x: r.maxX - rad, y: r.minY + rad), -.pi / 2, s / arc, topEnd, rightStart) }
        s -= arc
        if s < h { return (CGPoint(x: r.maxX, y: r.minY + rad + s), CGPoint(x: 1, y: 0), stray(1, s)) }
        s -= h
        if s < arc { return corner(CGPoint(x: r.maxX - rad, y: r.maxY - rad), 0, s / arc, rightEnd, bottomRight) }
        s -= arc
        if s < w { return (CGPoint(x: r.maxX - rad - s, y: r.maxY), CGPoint(x: 0, y: 1), stray(2, w - s)) }
        s -= w
        if s < arc { return corner(CGPoint(x: r.minX + rad, y: r.maxY - rad), .pi / 2, s / arc, bottomLeft, leftBottom) }
        s -= arc
        if s < h { return (CGPoint(x: r.minX, y: r.maxY - rad - s), CGPoint(x: -1, y: 0), stray(3, h - s)) }
        s -= h
        return corner(CGPoint(x: r.minX + rad, y: r.minY + rad), .pi, min(1, s / arc), leftTop, topStart)
    }
}

/// What joins the bubble to Gus, on its left edge: a small soft tail when he's talking, two little puffs
/// when he's thinking. Same white as the card, no outline.
struct BubbleTail: View {
    var thinking: Bool
    var body: some View {
        ZStack {
            if thinking {
                ZStack {
                    Circle().fill(Z.surface).frame(width: 9, height: 9).offset(x: 3, y: 6)
                    Circle().fill(Z.surface).frame(width: 5.5, height: 5.5).offset(x: -6, y: 14)
                }
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            } else {
                // A quick flick of a tail, a bit lopsided.
                Path { p in
                    p.move(to: CGPoint(x: 20, y: 1))
                    p.addQuadCurve(to: CGPoint(x: 1, y: 15), control: CGPoint(x: 12, y: 7))
                    p.addQuadCurve(to: CGPoint(x: 20, y: 21), control: CGPoint(x: 9, y: 22))
                    p.closeSubpath()
                }
                .fill(Z.surface)
                .shadow(color: .black.opacity(0.08), radius: 3, x: -1, y: 1)
                .transition(.scale(scale: 0.4, anchor: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: 22, height: 24)
    }
}
