import SwiftUI

/// Small label beside the kalash (a RealityView attachment): how many orbs are in, and how to cast the spell.
struct KalashPanelView: View {
    static let attachmentID = "KalashPanel"

    @Environment(OrchardViewModel.self) private var orchard

    var body: some View {
        // Hidden in SwiftUI, not by disabling its entity (see DragonImmersiveView).
        if let text {
            VStack(spacing: 4) {
                Text("Kalash \(orchard.kalash.storedCount)/\(Kalash.capacity)")
                    .font(.caption.bold().monospacedDigit())
                    .contentTransition(.numericText())
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if orchard.kalash.spell == .ready && orchard.twistProgress > 0 {
                    ProgressView(value: Double(orchard.twistProgress))
                        .tint(.cyan)
                }
            }
            .multilineTextAlignment(.center)
            .frame(width: 150)
            .padding(10)
            .glassBackgroundEffect()
            .animation(.default, value: orchard.kalash.storedCount)
        }
    }

    private var text: String? {
        switch orchard.kalash.spell {
        case .gathering:
            "Drop the orbs from the fruit in here."
        case .ready:
            orchard.isHandTrackingAvailable
                ? "Tap the kalash, or look at it, pinch and twist your wrist."
                : "Tap the kalash to cast the spell."
        case .forming, .formed:
            "The blue spell is forming…"
        case .flying, .delivered:
            nil
        }
    }
}

#Preview {
    KalashPanelView()
        .environment(OrchardViewModel())
}
