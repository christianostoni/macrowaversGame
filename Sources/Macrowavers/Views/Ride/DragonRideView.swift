#if os(visionOS)
import RealityKit
import SwiftUI

/// The story's last part, in its own full immersive space (the game's space hands over to it): the player rides on
/// the dragon's back out of the dark into the sky, steering it with both hands (`DragonRideSystem`), the air rushing
/// past; then chapter II, feeding the dragon the fruit floating among the clouds (not the bananas).
/// Closed by the system (Digital Crown), the story starts over from the launch window.
struct DragonRideView: View {
    static let spaceID = "DragonRideSpace"
    private static let tallyID = "FeastTally"

    @Environment(UntangleViewModel.self) private var untangle
    @Environment(OrchardViewModel.self) private var orchard
    @Environment(StoryViewModel.self) private var story
    @Environment(\.openWindow) private var openWindow
    /// Where the player's eyes are: the ride starts there.
    @State private var viewer = ViewerTracker()
    /// The hands on the dragon's horns.
    @State private var hands = HandTracker()

    var body: some View {
        RealityView { content, attachments in
            guard let ride = await DragonRideSceneBuilder.makeRide(story: story, viewer: viewer, hands: hands) else {
                return
            }
            content.add(ride)
            // Chapter II's title and the fruit tally ride along, in front of the eyes above the dragon's head.
            for (id, spot) in [(StoryPanelView.attachmentID, DragonRideSceneBuilder.panelSpot),
                               (Self.tallyID, DragonRideSceneBuilder.tallySpot)] {
                guard let attachment = attachments.entity(for: id) else { continue }
                attachment.position = spot
                ride.addChild(attachment)
            }
        } attachments: {
            Attachment(id: StoryPanelView.attachmentID) {
                StoryPanelView(hasBackdrop: true)
            }
            Attachment(id: Self.tallyID) {
                FeastTallyView()
            }
        }
        .task { await viewer.start() }
        .task {
            guard await hands.start() else { return }
            await hands.track()
        }
        .onAppear { untangle.immersiveSpaceState = .open }
        .onDisappear {
            viewer.stop()
            hands.stop()
            untangle.resetGame()
            orchard.reset()
            story.reset()
            untangle.immersiveSpaceState = .closed
            openWindow(id: ContentView.windowID)
        }
    }
}

/// Chapter II's goal while the player feeds the dragon: the fruit it has eaten, and a word when it spits out a
/// banana. Hidden in SwiftUI outside the feast (its attachment entity is never disabled).
private struct FeastTallyView: View {
    @Environment(StoryViewModel.self) private var story
    /// Shows "no bananas" for a moment after each one.
    @State private var isRefusing = false

    var body: some View {
        VStack(spacing: 8) {
            if story.step == .feast {
                Label {
                    Text(story.isFeastComplete ? "The dragon is full!"
                         : "\(story.plantsEaten) / \(StoryViewModel.plantsGoal)")
                        .monospacedDigit()
                } icon: {
                    Image(systemName: story.isFeastComplete ? "checkmark.circle.fill" : "leaf.fill")
                }
                .font(.title2.bold())
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .glassBackgroundEffect()
                .contentTransition(.numericText())
                .transition(.opacity)
                if isRefusing {
                    Text("Yuck! No bananas.")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: story.step)
        .animation(.spring(duration: 0.3), value: story.plantsEaten)
        .animation(.spring(duration: 0.3), value: isRefusing)
        .task(id: story.bananasRefused) {
            guard story.bananasRefused > 0 else { return }
            isRefusing = true
            try? await Task.sleep(for: .seconds(2))
            isRefusing = false
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview(immersionStyle: .full) {
    DragonRideView()
        .environment(UntangleViewModel())
        .environment(OrchardViewModel())
        .environment(StoryViewModel())
}
#endif
