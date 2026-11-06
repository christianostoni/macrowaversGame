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
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text(text)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                if orchard.elixirState == .ready && !orchard.isHandTrackingAvailable {
                    // No hand tracking (simulator, permission denied): there is no snap to read.
                    Button("Create the Elixir", systemImage: "sparkles") {
                        orchard.brewElixir()
                    }
                    .font(.caption)
                }
            }
            .multilineTextAlignment(.center)
            .frame(width: 190)
            // Clear of the capsule's round ends.
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            // A glass capsule with the name's ring light, like Start: the ring follows its edge exactly.
            .glassBackgroundEffect(in: .capsule)
            // Looked at, it lights up (the ring): the system's own highlight takes the capsule too, not the label's
            // rectangle (a button gets it from its border shape).
            .contentShape(.capsule)
            .contentShape(.hoverEffect, .capsule)
            .ringLight()
            // Room round it for the ring's glow: an attachment cuts off what spills past its bounds, and the glow
            // was cut square there (a window has room round Start).
            .padding(16)
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
                : "Every fruit hides a gem. Find \(missing) more."
        case .ready:
            // The hologram hand shows the snap: no words.
            return orchard.isHandTrackingAvailable ? nil : "Tap a gem to create the elixir."
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
