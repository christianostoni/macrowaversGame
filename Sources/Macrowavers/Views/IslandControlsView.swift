import SwiftUI

/// Island panel, inside the immersive space (a RealityView attachment, to the player's left): story status,
/// island rotation, dragon panel toggle and Restart Game, which closes the space and goes back to the launch
/// window.
struct IslandControlsView: View {
    static let attachmentID = "IslandControls"

    @Environment(UntangleViewModel.self) private var viewModel
    @Environment(OrchardViewModel.self) private var orchard
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        VStack(spacing: 16) {
            Text("The Floating Island")
                .font(.title)
            Text(storyStatus)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                HStack {
                    Button("Rotate Left", systemImage: "rotate.left") {
                        viewModel.rotateIsland(by: IslandPlacement.yawStep)
                    }
                    Button("Rotate Right", systemImage: "rotate.right") {
                        viewModel.rotateIsland(by: -IslandPlacement.yawStep)
                    }
                    Button("Reset Rotation", systemImage: "arrow.uturn.backward") {
                        viewModel.resetIslandRotation()
                    }
                }
                .labelStyle(.iconOnly)
                Text("Drag the island's rock to spin it, or rotate it with both hands.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button(viewModel.isDragonPanelVisible ? "Hide Dragon Panel" : "Show Dragon Panel", systemImage: "lizard") {
                viewModel.isDragonPanelVisible.toggle()
            }

            Divider()

            Button("Restart Game", systemImage: "arrow.counterclockwise.circle", role: .destructive) {
                Task { await restartGame() }
            }
            Text("Closes the island and starts over.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(width: 420)
        .padding(28)
        .glassBackgroundEffect()
    }

    private var storyStatus: String {
        switch viewModel.phase {
        case .captive:
            orchard.elixir.state == .flying
                ? "The elixir is flying to the dragon…"
                : "The dragon is circling the tree. Every fruit hides an ingredient: find three for the elixir."
        case .alerted: "The dragon is angry! Find three ingredients in the fruit and brew the elixir to calm it."
        case .approaching, .landing: "The dragon is coming to you."
        case .untangling: "Untangle the dragon: \(viewModel.crossingCount) crossings left."
        case .free: "The dragon is free!"
        case .gone: "The dragon flew back to the sky."
        }
    }

    /// Closes the immersive space: its onDisappear resets the game and reopens the launch window.
    private func restartGame() async {
        guard viewModel.immersiveSpaceState == .open else { return }
        viewModel.immersiveSpaceState = .inTransition
        await dismissImmersiveSpace()
    }
}

#Preview {
    IslandControlsView()
        .environment(UntangleViewModel())
        .environment(OrchardViewModel())
}
