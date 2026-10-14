import SwiftUI

/// Finestra principale (isola). All'avvio chiede di aprire l'isola; una volta aperta gestisce l'ambiente
/// (rotazione dell'isola) e il riavvio dell'intero gioco, che chiude anche il pannello del drago e lo spazio
/// immersivo. È l'unica finestra sempre presente: il pannello del drago si apre solo quando lo tocchi.
struct ContentView: View {
    static let windowID = "IslandWindow"

    @Environment(UntangleViewModel.self) private var viewModel
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

    // MARK: - Avvio

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

    // MARK: - Gestione dell'isola

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
        case .captive: "The dragon is circling the tree. Tap it."
        case .alerted: "The dragon is angry… it's coming down to you."
        case .approaching, .landing: "The dragon is coming to you."
        case .untangling: "Untangle the dragon: \(viewModel.crossingCount) crossings left."
        case .free: "The dragon is free!"
        case .gone: "The dragon flew back to the sky."
        }
    }

    // MARK: - Azioni (le azioni di finestre e spazi esistono solo nell'Environment: vivono nella View)

    private func openIsland() async {
        guard viewModel.immersiveSpaceState == .closed else { return }
        viewModel.immersiveSpaceState = .inTransition
        switch await openImmersiveSpace(id: DragonImmersiveView.spaceID) {
        case .opened:
            // Lo stato diventa `.open` nell'onAppear di DragonImmersiveView.
            break
        case .userCancelled, .error:
            viewModel.immersiveSpaceState = .closed
        @unknown default:
            viewModel.immersiveSpaceState = .closed
        }
    }

    /// Chiude pannello del drago e spazio immersivo e azzera tutto: si torna alla schermata d'avvio.
    private func restartGame() async {
        guard viewModel.immersiveSpaceState == .open else { return }
        viewModel.immersiveSpaceState = .inTransition
        dismissWindow(id: DragonPanelView.windowID)
        // Lo stato torna `.closed` (e il gioco si azzera) nell'onDisappear di DragonImmersiveView.
        await dismissImmersiveSpace()
        viewModel.resetGame()
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(UntangleViewModel())
}
