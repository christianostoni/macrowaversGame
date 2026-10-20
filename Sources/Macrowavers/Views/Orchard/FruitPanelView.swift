import SwiftUI

/// Small panel under the fruit in front of the player (a RealityView attachment, not a window):
/// what to do now, how many worms are left, back to the tree.
struct FruitPanelView: View {
    static let attachmentID = "FruitPanel"

    @Environment(OrchardViewModel.self) private var orchard

    var body: some View {
        // Hidden in SwiftUI, not by disabling its entity (see DragonImmersiveView).
        if orchard.focusedFruitID != nil { panel }
    }

    private var isEmpty: Bool { orchard.isFocusedFruitEmpty && orchard.isFocusedFruitExplored }

    private var panel: some View {
        VStack(spacing: 10) {
            Text(isEmpty ? "No ingredient left in this one" : title)
                .font(.headline)
            Text(hint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if orchard.focusedFruit?.kind == .apple && orchard.focusedOrb == .sealed {
                Text("Worms caught: \(orchard.caughtWorms)/\(orchard.wormCount)")
                    .font(.subheadline.monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.default, value: orchard.caughtWorms)
            }
            HStack(spacing: 12) {
                Button("Close It Again", systemImage: "arrow.counterclockwise") {
                    orchard.restartFruit()
                }
                if isEmpty {
                    Button("Back to the Tree", systemImage: "arrow.uturn.backward") {
                        orchard.back()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Back to the Tree", systemImage: "arrow.uturn.backward") {
                        orchard.back()
                    }
                }
            }
            .disabled(orchard.elixir.state == .flying)
        }
        .multilineTextAlignment(.center)
        .frame(width: 360)
        .padding(20)
        .glassBackgroundEffect()
    }

    private var title: String {
        switch orchard.focusedFruit?.kind {
        case .apple: "An apple from the tree"
        case .pomegranate: "A pomegranate from the tree"
        case .banana: "A banana from the tree"
        case .pineapple: "A pineapple from the tree"
        case nil: ""
        }
    }

    private var hint: String {
        switch orchard.focusedOrb {
        case .revealed:
            return orchard.elixir.state == .gathering
                ? "An ingredient for the elixir! It's joining the others around you."
                : "Three ingredients already orbit you: brew the elixir first."
        case .orbiting, .spent:
            return isEmpty ? "Its ingredient already orbits you. Put it back on the tree." : openHint
        case .sealed, nil:
            return openHint
        }
    }

    /// How to open the focused fruit.
    private var openHint: String {
        switch orchard.focusedFruit?.kind {
        case .apple:
            if orchard.appleOpening < orchard.wormSettings.minimumOpening { return "Pull the stem up to open the apple." }
            return orchard.focusedOrb == .sealed
                ? "Catch the worms! They burrow now and then, and get faster after each catch."
                : "Only worms in this one. Put it back on the tree."
        case .pomegranate:
            return orchard.pomegranateBurst ? "Drag the seeds around for fun." : "Pull it apart with both hands."
        case .banana:
            return "Pinch a strip of the peel and pull it outwards and down. Peel all four."
        case .pineapple:
            return orchard.isHandTrackingAvailable
                ? "Chop down through it with the edge of your hand, or tap it."
                : "Tap it to cut it open."
        case nil:
            return ""
        }
    }
}

#Preview {
    FruitPanelView()
        .environment(OrchardViewModel())
}
