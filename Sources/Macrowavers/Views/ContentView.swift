import SwiftUI

/// Main window (island). At launch it asks to open the island; once open it manages the environment
/// (island rotation) and the restart of the whole game, which also closes the dragon panel and the immersive
/// space. It is the only window always present: the dragon panel opens only when the dragon is tapped.
struct ContentView: View {
    static let windowID = "IslandWindow"

    @Environment(UntangleViewModel.self) private var viewModel
    @Environment(OrchardViewModel.self) private var orchard
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 20) {
            switch viewModel.immersiveSpaceState {
            case .closed:
                launch
            case .inTransition:
                ProgressView("Please wait…")
            case .open:
                islandControls
            }
        }
        .multilineTextAlignment(.center)
        .padding(40)
        .frame(width: 520)
    }

    // MARK: - Launch

    private var launch: some View {
        VStack(spacing: 20) {
            Text("Macrowavers")
                .font(.extraLargeTitle)
            Text("The Bound Dragon")
                .font(.title)
            Text("A floating island will appear in your room. A dragon is bound to the tree at its centre.")
                .foregroundStyle(.secondary)
            Button("Open the Island", systemImage: "mountain.2") {
                Task { await openIsland() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Island management

    private var islandControls: some View {
        VStack(spacing: 20) {
            Text("The Floating Island")
                .font(.extraLargeTitle2)
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

            Button("Dragon Panel", systemImage: "lizard") {
                openWindow(id: DragonPanelView.windowID)
            }

            Divider()

            Button("Restart Game", systemImage: "arrow.counterclockwise.circle", role: .destructive) {
                Task { await restartGame() }
            }
            Text("Closes the island and every panel, and starts over.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var storyStatus: String {
        switch viewModel.phase {
        case .captive:
            orchard.artifact == .flying
                ? "The artifact is flying to the dragon…"
                : "The dragon is circling the tree. Pick a fruit: one apple hides what can calm it."
        case .alerted: "The dragon is angry! Find the artifact in the tree's fruit to calm it."
        case .approaching, .landing: "The dragon is coming to you."
        case .untangling: "Untangle the dragon: \(viewModel.crossingCount) crossings left."
        case .free: "The dragon is free!"
        case .gone: "The dragon flew back to the sky."
        }
    }

    // MARK: - Actions (window and space actions exist only in the Environment: they live in the view)

    private func openIsland() async {
        guard viewModel.immersiveSpaceState == .closed else { return }
        viewModel.immersiveSpaceState = .inTransition
        switch await openImmersiveSpace(id: DragonImmersiveView.spaceID) {
        case .opened:
            // The state becomes `.open` in DragonImmersiveView's onAppear.
            break
        case .userCancelled, .error:
            viewModel.immersiveSpaceState = .closed
        @unknown default:
            viewModel.immersiveSpaceState = .closed
        }
    }

    /// Closes the dragon panel and the immersive space and resets everything: back to the launch screen.
    private func restartGame() async {
        guard viewModel.immersiveSpaceState == .open else { return }
        viewModel.immersiveSpaceState = .inTransition
        dismissWindow(id: DragonPanelView.windowID)
        // The state goes back to `.closed` (and the game resets) in DragonImmersiveView's onDisappear.
        await dismissImmersiveSpace()
        viewModel.resetGame()
        orchard.reset()
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(UntangleViewModel())
        .environment(OrchardViewModel())
}
