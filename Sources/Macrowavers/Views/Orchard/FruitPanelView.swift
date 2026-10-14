import SwiftUI

/// Small panel under the fruit in front of the player (a RealityView attachment, not a window):
/// what to do now, how many worms are left, back to the tree.
struct FruitPanelView: View {
    static let attachmentID = "FruitPanel"

    @Environment(OrchardViewModel.self) private var orchard

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.headline)
            Text(hint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if orchard.focusedFruit?.kind == .apple && orchard.artifact == .guarded {
                Text("Worms caught: \(orchard.caughtWorms)/\(orchard.wormCount)")
                    .font(.subheadline.monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.default, value: orchard.caughtWorms)
            }
            HStack(spacing: 12) {
                Button("Close It Again", systemImage: "arrow.counterclockwise") {
                    orchard.restartFruit()
                }
                Button("Back to the Tree", systemImage: "arrow.uturn.backward") {
                    orchard.back()
                }
            }
            .disabled(orchard.artifact == .flying)
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
        case nil: ""
        }
    }

    private var hint: String {
        switch orchard.focusedFruit?.kind {
        case .apple: appleHint
        case .pomegranate:
            orchard.pomegranateBurst
                ? "Drag the seeds around. No artifact in here: try an apple."
                : "Pull it apart with both hands."
        case nil: ""
        }
    }

    private var appleHint: String {
        if orchard.appleOpening < orchard.wormSettings.minimumOpening {
            return "Pull the stem up to open the apple."
        }
        switch orchard.artifact {
        case .guarded:
            return "Catch the worms! They burrow now and then, and get faster after each catch."
        case .revealed:
            return orchard.focusedFruitID == orchard.artifactFruitID
                ? "Something glows inside! Tap it to send it to the dragon."
                : "Only worms in this one."
        case .flying:
            return "The artifact flies to the dragon…"
        case .hidden, .used:
            return "Only worms in this one."
        }
    }
}

#Preview {
    FruitPanelView()
        .environment(OrchardViewModel())
}
