import SwiftUI

/// Finestra di controllo: avvia lo spazio immersivo e mostra lo stato del puzzle.
struct ControlPanelView: View {
    static let windowID = "UntangleControlPanel"

    @Environment(UntangleViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 16) {
            #if os(visionOS)
            if viewModel.immersiveSpaceState == .open {
                status
            } else {
                Text("Untangle the Dragon")
                    .font(.extraLargeTitle2)
                Text("A floating island will appear in your room, with a dragon bound to its tree.")
                    .foregroundStyle(.secondary)
            }
            ImmersiveSpaceToggle()
            #else
            Text("This mini-game requires Apple Vision Pro.")
            #endif
        }
        .multilineTextAlignment(.center)
        .padding(32)
    }

    @ViewBuilder
    private var status: some View {
        VStack(spacing: 12) {
            switch viewModel.phase {
            case .captive:
                Text("The Bound Dragon")
                    .font(.extraLargeTitle2)
                Text("A dragon is circling the tree on the floating island. Look at it and tap to call it to you.")
                    .foregroundStyle(.secondary)
            case .approaching:
                Text("The dragon is coming…")
                    .font(.extraLargeTitle2)
                Text("Stay still: it wants to look at you.")
                    .foregroundStyle(.secondary)
            case .landing:
                Text("The dragon is landing")
                    .font(.extraLargeTitle2)
                Text("Careful, it's getting all tangled up!")
                    .foregroundStyle(.secondary)
            case .untangling:
                puzzleStatus
            case .free, .gone:
                Text("The dragon is free! 🐉")
                    .font(.extraLargeTitle2)
                Text(freedomMessage)
                    .foregroundStyle(.secondary)
                Button("Play Again", systemImage: "arrow.counterclockwise") {
                    viewModel.playAgain()
                }
            }
        }
        .animation(.default, value: viewModel.phase)
    }

    private var puzzleStatus: some View {
        VStack(spacing: 12) {
            Text("Crossings left: \(viewModel.crossingCount)")
                .font(.title)
                .contentTransition(.numericText())
                .animation(.default, value: viewModel.crossingCount)
            Text(moodMessage)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(viewModel.restlessness))
                .tint(.orange)
                .opacity(viewModel.restlessness > 0 ? 1 : 0)
            Button("Restart", systemImage: "arrow.counterclockwise") {
                viewModel.restartPuzzle()
            }
            Divider()
            placementControls
        }
    }

    private var freedomMessage: String {
        if viewModel.phase == .gone { return "It flew back to the sky. Thank you, knight!" }
        return viewModel.isFlying ? "It's thanking you before flying home…" : "It's spreading its wings…"
    }

    private var moodMessage: String {
        switch viewModel.mood {
        case .calm: "Pinch and drag the dragon's body. You can use both hands."
        case .annoyed: "Easy! The dragon doesn't like being pulled!"
        case .restless: "The dragon is getting restless…"
        case .wriggling:
            switch viewModel.action {
            case .rearUp: "The dragon rears up and roars!"
            case .turn: "The dragon is turning around!"
            case .tailLash: "Watch out for its tail!"
            case .coil: "The dragon is coiling up!"
            case nil: "The dragon is thrashing!"
            }
        case .free: ""
        }
    }

    /// Alternativa ai gesti per sistemare la piattaforma (comoda anche nel simulatore).
    private var placementControls: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Tilt")
                Slider(value: Binding(get: { Double(viewModel.placement.tilt) },
                                      set: { viewModel.setTilt(Float($0)) }),
                       in: Double(PlayAreaPlacement.tiltRange.lowerBound)...Double(PlayAreaPlacement.tiltRange.upperBound))
            }
            HStack {
                Button("Rotate Left", systemImage: "rotate.left") {
                    viewModel.rotatePlayArea(yaw: viewModel.placement.yaw + .pi / 8)
                }
                Button("Rotate Right", systemImage: "rotate.right") {
                    viewModel.rotatePlayArea(yaw: viewModel.placement.yaw - .pi / 8)
                }
                Button("Reset Position", systemImage: "arrow.uturn.backward") {
                    viewModel.resetPlacement()
                }
            }
            .labelStyle(.iconOnly)
            Text("Drag the platform or its handle to move it. Rotate it with both hands.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#if os(visionOS)
/// Apre e chiude lo spazio immersivo. Le azioni `openImmersiveSpace`/`dismissImmersiveSpace`
/// esistono solo nell'Environment di SwiftUI, quindi vivono nella View; lo stato è nel ViewModel.
private struct ImmersiveSpaceToggle: View {
    @Environment(UntangleViewModel.self) private var viewModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        Button(viewModel.immersiveSpaceState == .open ? "Close" : "Start") {
            Task { await toggle() }
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.immersiveSpaceState == .inTransition)
    }

    private func toggle() async {
        switch viewModel.immersiveSpaceState {
        case .open:
            viewModel.immersiveSpaceState = .inTransition
            // Lo stato torna `.closed` nell'onDisappear di DragonImmersiveView.
            await dismissImmersiveSpace()
        case .closed:
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
        case .inTransition:
            break
        }
    }
}
#endif

#Preview {
    ControlPanelView()
        .environment(UntangleViewModel())
}
