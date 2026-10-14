import SwiftUI

/// Dragon panel: a single window (`Window`, never duplicated) that opens when the player taps the dragon.
/// Shows the dragon's state, also as debug info, the mini-game controls and the scene restart.
/// The immersive space and the island are managed by the main window (`ContentView`).
struct DragonPanelView: View {
    static let windowID = "DragonPanel"

    @Environment(UntangleViewModel.self) private var viewModel
    @Environment(OrchardViewModel.self) private var orchard

    var body: some View {
        VStack(spacing: 16) {
            status
            Divider()
            debugInfo
            Button("Restart Scene", systemImage: "arrow.counterclockwise") {
                viewModel.restartScene()
                orchard.reset()
            }
            Text("Puts the dragon back around the tree and the fruit back on its branches.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(width: 480)
        .animation(.default, value: viewModel.phase)
    }

    @ViewBuilder
    private var status: some View {
        switch viewModel.phase {
        case .captive:
            headline("The dragon is circling the tree",
                     detail: orchard.artifact == .flying
                        ? "The artifact is flying to the dragon…"
                        : "Something hidden in the tree's fruit can calm it. Open an apple and catch its worms.")
        case .alerted:
            headline("The dragon is getting angry!",
                     detail: "It's glaring at you, growling and snorting smoke. It won't come near you: "
                        + "find the artifact in the tree's fruit to calm it.")
            Button("Call It Now", systemImage: "hand.wave") {
                viewModel.callDragon()
            }
            Text("Debug: skips the artifact.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .approaching:
            headline("The dragon is coming…", detail: "Stay still: it wants to look at you.")
        case .landing:
            headline("The dragon is landing", detail: "Careful, it's getting all tangled up!")
        case .untangling:
            puzzleStatus
        case .free, .gone:
            headline("The dragon is free! 🐉", detail: freedomMessage)
        }
    }

    private func headline(_ title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title)
            Text(detail)
                .foregroundStyle(.secondary)
        }
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
            Button("Restart Puzzle", systemImage: "arrow.triangle.2.circlepath") {
                viewModel.restartPuzzle()
            }
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

    /// Internal state of the dragon and the fruit, handy to test the flow in the simulator and on device.
    private var debugInfo: some View {
        GroupBox("Debug") {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Phase", value: String(describing: viewModel.phase))
                LabeledContent("Mood", value: String(describing: viewModel.mood))
                LabeledContent("Action", value: viewModel.action.map { String(describing: $0) } ?? "none")
                LabeledContent("Crossings", value: "\(viewModel.crossingCount)")
                LabeledContent("Restlessness", value: viewModel.restlessness.formatted(.percent.precision(.fractionLength(0))))
                LabeledContent("Strain", value: viewModel.strain.formatted(.percent.precision(.fractionLength(0))))
                LabeledContent("Fruit", value: orchard.focusedFruit.map { "\($0.kind) #\($0.id)" } ?? "on the tree")
                LabeledContent("Apple opening", value: orchard.appleOpening.formatted(.percent.precision(.fractionLength(0))))
                LabeledContent("Worms", value: "\(orchard.caughtWorms)/\(orchard.wormCount)")
                LabeledContent("Artifact", value: String(describing: orchard.artifact))
            }
            .font(.footnote.monospaced())
        }
    }

    /// Alternative to gestures to arrange the tangle (handy in the simulator too).
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
            Text("Tilt or rotate the dragon to see the knot better.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    DragonPanelView()
        .environment(UntangleViewModel())
        .environment(OrchardViewModel())
}
