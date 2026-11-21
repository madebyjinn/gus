import SwiftUI
import AppKit

/// The Gus look: everything the rest of the app asks of the otter goes through here.
@MainActor
enum GusTheme {
    static let available = true

    enum Reaction { case greet, say, cheer, wink }
    static func react(_ reaction: Reaction) {
        let gus = OtterActor.shared
        gus.start()
        switch reaction {
        case .greet: gus.greet()
        case .say: gus.say()
        case .cheer: gus.cheer()
        case .wink: gus.wink()
        }
    }

    /// The bar came up or went away in the Gus look.
    static func barShown(_ showing: Bool) {
        if showing { OtterActor.shared.start(); OtterActor.shared.greet() } else { OtterActor.shared.stop() }
    }

    static func settle(thinking: Bool, hasResults: Bool, empty: Bool) {
        OtterActor.shared.settle(thinking: thinking, hasResults: hasResults, empty: empty)
    }

    struct Figure: View { var body: some View { OtterFigure() } }

    struct LookPreview: View {
        var body: some View {
            HStack(spacing: 4) {
                if let img = OtterActor.image(.idle) {
                    Image(nsImage: img).resizable().scaledToFit().frame(width: 30, height: 30)
                }
                WobblyBubble(seed: 2.1, wobble: 0.5, radius: 7, inset: 0).fill(Color.white)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    .frame(width: 64, height: 22)
            }
        }
    }

    /// Solid and Glass clip the card to a rounded rectangle. The Gus look keeps Solid's white card and soft
    /// shadow, and adds only what makes it speech: a small tail toward Gus, and, while he's thinking, an
    /// edge that puffs into a cloud with two little thought puffs.
    struct Dress: ViewModifier {
        let thinking: Bool
        func body(content: Content) -> some View {
            if Z.gus {
                let cloud: CGFloat = thinking ? 1 : 0
                // Drawn by hand: the edge wanders, the corners don't quite match, and it sits a touch askew.
                content
                    .clipShape(WobblyBubble(cloud: 0, seed: 2.1, wobble: 1, radius: Bar.radius + 4, inset: 0))
                    .background {
                        WobblyBubble(cloud: cloud, seed: 2.1, wobble: 1, radius: Bar.radius + 4, inset: 0)
                            .fill(Z.surface)
                            // One soft shadow: two blurred shadows on a shape that redraws every frame cost frames.
                            .shadow(color: .black.opacity(0.13), radius: 14, y: 6)
                    }
                    .background(alignment: .topLeading) { BubbleTail(thinking: thinking).offset(x: -15, y: 12) }
            } else {
                content.clipShape(Z.rect(Bar.radius))
            }
        }
    }
}
