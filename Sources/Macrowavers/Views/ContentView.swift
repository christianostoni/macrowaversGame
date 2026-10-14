import SwiftUI

/// Launch window: asks to open the island. Once the immersive space is open this window closes, so it can
/// never overlap the island, the dragon or the fruit: from then on the controls are panels inside the space
/// (`IslandControlsView`, `DragonPanelView`), placed to the sides of the play area. The window comes back
/// when the space closes (Restart Game or Digital Crown).
struct ContentView: View {
    static let windowID = "IslandWindow"

    @Environment(UntangleViewModel.self) private var viewModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 20) {
            Text("Macrowavers")
                .font(.extraLargeTitle)
            Text("The Bound Dragon")
                .font(.title)
            Text("A floating island will appear in your room. A dragon is bound to the tree at its centre.")
                .foregroundStyle(.secondary)
            if viewModel.immersiveSpaceState == .closed {
                Button("Open the Island", systemImage: "mountain.2") {
                    Task { await openIsland() }
                }
                .buttonStyle(.borderedProminent)
            } else {
                ProgressView("Opening the island…")
            }
        }
        .multilineTextAlignment(.center)
        .padding(40)
        .frame(width: 520)
    }

    /// Window and space actions exist only in the Environment: they live in the view.
    private func openIsland() async {
        guard viewModel.immersiveSpaceState == .closed else { return }
        viewModel.immersiveSpaceState = .inTransition
        switch await openImmersiveSpace(id: DragonImmersiveView.spaceID) {
        case .opened:
            // The state becomes `.open` in DragonImmersiveView's onAppear. The window steps aside.
            dismissWindow(id: Self.windowID)
        case .userCancelled, .error:
            viewModel.immersiveSpaceState = .closed
        @unknown default:
            viewModel.immersiveSpaceState = .closed
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(UntangleViewModel())
}
