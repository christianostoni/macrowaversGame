import SwiftUI

/// Pannello del drago: finestra unica (`Window`, mai duplicata) che si apre quando l'utente tocca il drago.
/// Mostra lo stato del drago, anche in forma di debug, i comandi del minigioco e il riavvio della scena.
/// Lo spazio immersivo e l'isola li gestisce la finestra principale (`ContentView`).
struct DragonPanelView: View {
    static let windowID = "DragonPanel"

    @Environment(UntangleViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 16) {
            status
            Divider()
            debugInfo
            Button("Restart Scene", systemImage: "arrow.counterclockwise") {
                viewModel.restartScene()
            }
            Text("Puts the dragon back around the tree.")
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
            headline("The dragon is circling the tree", detail: "Look at it and tap it to disturb it.")
        case .alerted:
            headline("The dragon is getting angry!",
                     detail: "It's glaring at you, growling and snorting smoke. Call it down when you're ready.")
            Button("Call the Dragon", systemImage: "hand.wave") {
                viewModel.callDragon()
            }
            .buttonStyle(.borderedProminent)
            Text("Debug: the artifact that calms the dragon will replace this button.")
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

    /// Stato interno del drago, utile per provare il flusso nel simulatore e sul dispositivo.
    private var debugInfo: some View {
        GroupBox("Debug") {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Phase", value: String(describing: viewModel.phase))
                LabeledContent("Mood", value: String(describing: viewModel.mood))
                LabeledContent("Action", value: viewModel.action.map { String(describing: $0) } ?? "none")
                LabeledContent("Crossings", value: "\(viewModel.crossingCount)")
                LabeledContent("Restlessness", value: viewModel.restlessness.formatted(.percent.precision(.fractionLength(0))))
                LabeledContent("Strain", value: viewModel.strain.formatted(.percent.precision(.fractionLength(0))))
            }
            .font(.footnote.monospaced())
        }
    }

    /// Alternativa ai gesti per sistemare il groviglio (comoda anche nel simulatore).
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
}
