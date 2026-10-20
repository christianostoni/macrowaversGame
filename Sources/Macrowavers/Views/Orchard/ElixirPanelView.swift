import SwiftUI

/// Small label under the ingredients' orbit, in front of the player (a RealityView attachment): how many
/// ingredients orbit, and how to brew the elixir.
struct ElixirPanelView: View {
    static let attachmentID = "ElixirPanel"

    @Environment(OrchardViewModel.self) private var orchard

    var body: some View {
        // Hidden in SwiftUI, not by disabling its entity (see DragonImmersiveView).
        if let text {
            VStack(spacing: 6) {
                Text("Elixir \(orchard.elixir.orbitingCount)/\(Elixir.ingredientCount)")
                    .font(.caption.bold().monospacedDigit())
                    .contentTransition(.numericText())
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if orchard.elixir.state == .ready && !orchard.isHandTrackingAvailable {
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
            .animation(.default, value: orchard.elixir.orbitingCount)
        }
    }

    private var text: String? {
        // The fruit's own panel speaks while a fruit is close.
        guard orchard.focusedFruitID == nil else { return nil }
        switch orchard.elixir.state {
        case .gathering:
            let missing = Elixir.ingredientCount - orchard.elixir.orbitingCount
            return orchard.elixir.orbitingCount == 0
                ? nil
                : "Every fruit hides an ingredient. Find \(missing) more."
        case .ready:
            guard orchard.isHandTrackingAvailable else { return "Tap an ingredient to brew the elixir." }
            return orchard.isSnapLoaded
                ? "Now snap!"
                : "Press your thumb on your middle finger and snap to brew the elixir."
        case .fusing, .brewed:
            return "The elixir is brewing…"
        case .flying, .delivered:
            return nil
        }
    }
}

#Preview {
    ElixirPanelView()
        .environment(OrchardViewModel())
}
