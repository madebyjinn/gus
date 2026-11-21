import AppKit

/// Gus in the menu bar: an otter's head, drawn as vectors on an 18 pt grid in whatever pose it's in.
/// Template images, so macOS tints them for light and dark menu bars; each pose is drawn once and cached.
enum OtterGlyph {
    struct Pose: Hashable {
        enum Eyes: Hashable { case open, happy, closed, sleepy, wink }
        var eyes: Eyes = .open
        /// Where the pupils look, -1…1 each way.
        var lookX: Int = 0
        var lookY: Int = 0
        var mouthOpen = false
        /// Ear twitch: -1 left, 1 right, 0 none.
        var ear = 0
        /// Head bob in tenths of a point (a hop is a few of these in a row).
        var bob = 0
        /// Head tilt in degrees.
        var tilt = 0
    }

    @MainActor private static var cache: [Pose: NSImage] = [:]

    @MainActor static func image(_ pose: Pose = Pose()) -> NSImage {
        if let hit = cache[pose] { return hit }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: 9, y: 9)
            ctx.rotate(by: CGFloat(pose.tilt) * .pi / 180)
            ctx.translateBy(x: -9, y: -9 + CGFloat(pose.bob) / 10)
            draw(pose, in: ctx)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Gus"
        if cache.count > 200 { cache.removeAll() }
        cache[pose] = image
        return image
    }

    private static func draw(_ pose: Pose, in ctx: CGContext) {
        NSColor.black.setFill()
        NSColor.black.setStroke()

        // Ears, tucked at the top corners; a twitch flicks one up.
        let leftUp: CGFloat = pose.ear == -1 ? 0.9 : 0
        let rightUp: CGFloat = pose.ear == 1 ? 0.9 : 0
        NSBezierPath(ovalIn: NSRect(x: 0.5, y: 10.9 + leftUp, width: 2.6, height: 2.6)).fill()
        NSBezierPath(ovalIn: NSRect(x: 14.9, y: 10.9 + rightUp, width: 2.6, height: 2.6)).fill()

        // A big, wide, slightly flat head that fills the slot.
        NSBezierPath(roundedRect: NSRect(x: 0.8, y: 2.0, width: 16.4, height: 12.0), xRadius: 7.4, yRadius: 5.9).fill()

        ctx.setBlendMode(.clear)
        // Muzzle: the two round whisker pads that make it an otter, not a bear.
        NSBezierPath(ovalIn: NSRect(x: 4.2, y: 2.7, width: 5.2, height: 4.4)).fill()
        NSBezierPath(ovalIn: NSRect(x: 8.6, y: 2.7, width: 5.2, height: 4.4)).fill()
        // Eyes: big enough to read at menu-bar size.
        let eyeY: CGFloat = 9.9
        for (i, x) in [5.3, 12.7].enumerated() {
            switch pose.eyes {
            case .open:
                let dx = CGFloat(pose.lookX) * 0.9, dy = CGFloat(pose.lookY) * 0.6
                NSBezierPath(ovalIn: NSRect(x: x - 1.55 + dx, y: eyeY - 1.6 + dy, width: 3.1, height: 3.2)).fill()
            case .happy:
                arc(at: x, y: eyeY - 0.7, up: true)
            case .closed:
                line(from: NSPoint(x: x - 1.5, y: eyeY), to: NSPoint(x: x + 1.5, y: eyeY))
            case .sleepy:
                arc(at: x, y: eyeY + 0.6, up: false)
            case .wink:
                if i == 0 { NSBezierPath(ovalIn: NSRect(x: x - 1.55, y: eyeY - 1.6, width: 3.1, height: 3.2)).fill() }
                else { arc(at: x, y: eyeY - 0.7, up: true) }
            }
        }
        ctx.setBlendMode(.normal)

        // Just a nose (and a little "o" when it's excited).
        NSBezierPath(roundedRect: NSRect(x: 7.2, y: 5.5, width: 3.6, height: 2.3), xRadius: 1.15, yRadius: 1.15).fill()
        if pose.mouthOpen {
            NSBezierPath(ovalIn: NSRect(x: 8.1, y: 2.9, width: 1.8, height: 1.7)).fill()
        }
    }

    private static func arc(at x: CGFloat, y: CGFloat, up: Bool) {
        let p = NSBezierPath()
        let lift: CGFloat = up ? 1.8 : -1.3
        p.move(to: NSPoint(x: x - 1.6, y: y))
        p.curve(to: NSPoint(x: x + 1.6, y: y), controlPoint1: NSPoint(x: x - 1.1, y: y + lift), controlPoint2: NSPoint(x: x + 1.1, y: y + lift))
        p.lineWidth = 1.3; p.lineCapStyle = .round; p.stroke()
    }

    private static func line(from a: NSPoint, to b: NSPoint) {
        let p = NSBezierPath(); p.move(to: a); p.line(to: b)
        p.lineWidth = 1.3; p.lineCapStyle = .round; p.stroke()
    }
}

/// Brings the menu-bar otter to life without costing anything at rest: it redraws only when its pose
/// changes. Its eyes follow the pointer, it blinks every few seconds, twitches an ear or tilts its head
/// now and then, dozes off after two quiet minutes, hops when Gus opens, and winks when you copy.
@MainActor
final class MenuOtter {
    private weak var button: NSStatusBarButton?
    private var pose = OtterGlyph.Pose() { didSet { if pose != oldValue { button?.image = OtterGlyph.image(pose) } } }
    private var monitors: [Any] = []
    private var lastActivity = Date()
    private var busy = false          // a short animation is playing
    private var open = false          // Gus's bar is showing
    private var generation = 0        // cancels a playing animation when another starts

    init(button: NSStatusBarButton?) {
        self.button = button
        button?.image = OtterGlyph.image(pose)
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .keyDown], handler: { [weak self] _ in
            Task { @MainActor in self?.activity() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .keyDown], handler: { [weak self] e in
            Task { @MainActor in self?.activity() }
            return e
        }) { monitors.append(m) }
        scheduleBlink()
        scheduleFidget()
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkDoze() }
        }
    }

    // MARK: Moods

    func barOpened() {
        open = true
        lastActivity = Date()
        play([(.init(eyes: .happy), 0.0), (.init(eyes: .happy, mouthOpen: true, bob: 5), 0.07),
              (.init(eyes: .happy, mouthOpen: true, bob: 9), 0.07), (.init(eyes: .happy, bob: 4), 0.08),
              (.init(eyes: .happy, bob: -3), 0.08), (.init(eyes: .happy), 0.07)],
             rest: .init(eyes: .happy))
    }

    func barClosed() {
        open = false
        play([(.init(eyes: .open), 0.0)], rest: .init(eyes: .open))
    }

    func copied() {
        play([(.init(eyes: .wink, ear: 1, tilt: -6), 0.0)], hold: 0.6,
             rest: open ? .init(eyes: .happy) : .init(eyes: .open))
    }

    // MARK: Idle life

    private func activity() {
        let wasAsleep = pose.eyes == .sleepy
        lastActivity = Date()
        if wasAsleep {
            play([(.init(eyes: .closed, ear: -1), 0.0), (.init(eyes: .open, ear: 1), 0.14), (.init(eyes: .open), 0.18)],
                 rest: .init(eyes: .open))
            return
        }
        guard !busy, !open, pose.eyes == .open, let frame = button?.window?.frame else { return }
        // Look toward the pointer: left, ahead or right, and down when it's well below the menu bar.
        let p = NSEvent.mouseLocation
        let dx = p.x - frame.midX, dy = p.y - frame.midY
        var next = pose
        next.lookX = abs(dx) < 140 ? 0 : (dx > 0 ? 1 : -1)
        next.lookY = dy < -240 ? -1 : 0
        pose = next
    }

    private func checkDoze() {
        guard !open, !busy, Date().timeIntervalSince(lastActivity) > 120 else { return }
        pose = .init(eyes: .sleepy, bob: -5, tilt: 5)
    }

    private func scheduleBlink() {
        Timer.scheduledTimer(withTimeInterval: .random(in: 3.0...7.0), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.busy, !self.open, self.pose.eyes == .open {
                    let back = self.pose
                    var shut = back; shut.eyes = .closed
                    self.play([(shut, 0.0)], hold: 0.11, rest: back)
                }
                self.scheduleBlink()
            }
        }
    }

    /// Every half minute or so: an ear flick, a glance around, or a little head tilt.
    private func scheduleFidget() {
        Timer.scheduledTimer(withTimeInterval: .random(in: 18...40), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.busy, !self.open, self.pose.eyes == .open {
                    let base = self.pose
                    var a = base, b = base
                    switch Int.random(in: 0..<3) {
                    case 0: a.ear = -1; b.ear = 1
                    case 1: a.lookX = -1; b.lookX = 1
                    default: a.tilt = 8; b.tilt = -6
                    }
                    self.play([(a, 0.0), (base, 0.16), (b, 0.16), (base, 0.16)], rest: base)
                }
                self.scheduleFidget()
            }
        }
    }

    /// Steps through poses (each with the delay before it), holds, then settles on `rest`.
    private func play(_ frames: [(OtterGlyph.Pose, Double)], hold: Double = 0.1, rest: OtterGlyph.Pose) {
        generation += 1
        let run = generation
        busy = true
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
            self.pose = rest
            self.busy = false
        }
    }
}
