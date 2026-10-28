import SwiftUI

/// Small label under the ingredients' orbit, at the player's side (a RealityView attachment): how many
/// ingredients orbit. With all of them in orbit it gives way to the hologram hand that shows the snap
/// (`SnapHintRig`); only without hand tracking it stays, to say the tap brews the elixir.
struct ElixirPanelView: View {
    static let attachmentID = "ElixirPanel"

    @Environment(OrchardViewModel.self) private var orchard

    var body: some View {
        // Hidden in SwiftUI, not by disabling its entity (see DragonImmersiveView).
        if let text {
            VStack(spacing: 6) {
                Text("Elixir \(orchard.orbitingCount)/\(Elixir.ingredientCount)")
                    .font(.caption.bold().monospacedDigit())
                    .contentTransition(.numericText())
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if orchard.elixirState == .ready && !orchard.isHandTrackingAvailable {
                    // No hand tracking (simulator, permission denied): there is no snap to read.
                    Button("Brew the Elixir", systemImage: "sparkles") {
                        orchard.brewElixir()
                    }
                    .font(.caption)
                }
            }
            .multilineTextAlignment(.center)
            .frame(width: 190)
            .padding(10)
            .glassBackgroundEffect()
            .animation(.default, value: orchard.orbitingCount)
        }
    }

    private var text: String? {
        // The fruit's own panel speaks while a fruit is close.
        guard orchard.focusedFruitID == nil else { return nil }
        switch orchard.elixirState {
        case .gathering:
            let missing = Elixir.ingredientCount - orchard.orbitingCount
            return orchard.orbitingCount == 0
                ? nil
                : "Every fruit hides an ingredient. Find \(missing) more."
        case .ready:
            // The hologram hand shows the snap: no words.
            return orchard.isHandTrackingAvailable ? nil : "Tap an ingredient to brew the elixir."
        case .fusing, .brewed, .flying, .delivered, .poured:
            // The snap is done: the brew speaks for itself.
            return nil
        }
    }
}

#Preview {
    ElixirPanelView()
        .environment(OrchardViewModel())
}
