#if os(visionOS)
import RealityKit
import SwiftUI

/// The story's last part, in its own full immersive space (the game's space hands over to it): the player rides on
/// the dragon's back out of the dark into the sky, steering it with both hands (`DragonRideSystem`), the air rushing
/// past; then chapter II, feeding the dragon fruit floating in the sky, a sky harder as they do well (not the bananas, not the
/// poisoned ones: a snap of the fingers breathes fire on them), until it is full and flies into the star medallion
/// they lit up, where the story ends. "The End" (or the Digital Crown) closes it: the story starts over from the
/// launch window.
struct DragonRideView: View {
    static let spaceID = "DragonRideSpace"
    private static let tallyID = "FeastTally"
    private static let hintID = "HornsHint"
    private static let loadingID = "RideLoading"
    /// The spinner's distance in front of the eyes (m).
    private static let loadingDistance: Float = 1.2

    @Environment(UntangleViewModel.self) private var untangle
    @Environment(OrchardViewModel.self) private var orchard
    @Environment(StoryViewModel.self) private var story
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    /// Where the player's eyes are: the ride starts there.
    @State private var viewer = ViewerTracker()
    /// The hands on the dragon's horns.
    @State private var hands = HandTracker()
    /// Whether the hands hold the horns, for the hint.
    @State private var status = RideStatus()
    /// The ride's world is built (the dragon, the sky, the fruit): the spinner goes.
    @State private var isLoaded = false
    /// The ride's music, in the player's ears (the island's closed with its space).
    @State private var music = GameMusic()

    var body: some View {
        RealityView { content, attachments in
            content.add(music.entity)
            // A spinner in the dark while the ride's assets load, placed once in front of the eyes.
            if let loading = attachments.entity(for: Self.loadingID) {
                let anchor = AnchorEntity(.head, trackingMode: .once)
                loading.position = SIMD3(0, 0, -Self.loadingDistance)
                anchor.addChild(loading)
                content.add(anchor)
            }
            guard let ride = await DragonRideSceneBuilder.makeRide(story: story, status: status, viewer: viewer,
                                                                    hands: hands) else {
                isLoaded = true
                return
            }
            content.add(ride)
            isLoaded = true
            // Chapter II's title, the fruit tally and how to hold the horns ride along, in front of the eyes.
            for (id, spot) in [(StoryPanelView.attachmentID, DragonRideSceneBuilder.panelSpot),
                               (Self.tallyID, DragonRideSceneBuilder.tallySpot),
                               (Self.hintID, DragonRideSceneBuilder.hintSpot)] {
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
            Attachment(id: Self.hintID) {
                HornsHintView(status: status)
            }
            Attachment(id: Self.loadingID) {
                RideLoadingView(isLoaded: isLoaded)
            }
        }
        // The music fades in out of the dark, follows the story and fades out as the space closes.
        .onChange(of: MusicTrack.riding(story: story.step), initial: true) { _, track in
            music.play(track)
        }
        .task { await music.load(MusicTrack.ridingTracks) }
        .task { await viewer.start() }
        .task {
            guard await hands.start() else { return }
            await hands.track()
        }
        .onAppear { untangle.immersiveSpaceState = .open }
        // "The End": the space closes; `onDisappear` starts the story over from the launch window.
        .onChange(of: story.step == .ended) { _, isOver in
            guard isOver else { return }
            Task { await dismissImmersiveSpace() }
        }
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

/// The dragon tangling and untangling (`DragonLoadingView`) while the ride's world loads. Hidden in SwiftUI once it
/// is built (its attachment entity is never disabled).
private struct RideLoadingView: View {
    let isLoaded: Bool

    var body: some View {
        ZStack {
            if !isLoaded {
                VStack(spacing: 12) {
                    DragonLoadingView()
                    Text("Loading…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .glassBackgroundEffect()
                .transition(.opacity)
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isLoaded)
    }
}

/// How to steer, over the dragon's head while the hands don't hold its horns: pinch with both hands, then the arms
/// lead the dragon. Hidden in SwiftUI while they hold them (and for a moment after they let go: a hand let go to
/// snap the fire comes back), under a page, in the finale and without hand tracking (autopilot).
private struct HornsHintView: View {
    /// How long the hands stay off the horns before the hint comes back (s).
    private static let letGoDelay: Duration = .seconds(1.5)

    let status: RideStatus
    @Environment(StoryViewModel.self) private var story
    /// The hands have been off the horns for a while.
    @State private var isLetGo = true

    private var isShown: Bool {
        status.isFlying && status.canSteer && isLetGo && story.step.page == nil
            && (story.step == .ride || story.step == .feast)
    }

    var body: some View {
        ZStack {
            if isShown {
                VStack(spacing: 10) {
                    HStack(spacing: 16) {
                        Image(systemName: "hand.pinch.fill")
                            .scaleEffect(x: -1)
                        Image(systemName: "hand.pinch.fill")
                    }
                    .font(.largeTitle)
                    Text("Pinch with both hands to hold the horns")
                        .font(.title3.bold())
                    Text("Raise or lower your arms to climb or dive.\nMove them to a side to turn.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(24)
                .glassBackgroundEffect()
                .transition(.opacity)
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: isShown)
        .task(id: status.isHolding) {
            guard !status.isHolding else {
                isLetGo = false
                return
            }
            // The very first time, at once; after a hold, only once the hands have stayed off for a while.
            if !isLetGo {
                try? await Task.sleep(for: Self.letGoDelay)
                guard !Task.isCancelled else { return }
            }
            isLetGo = true
        }
    }
}

/// Chapter II's tally while the player feeds the dragon: its hearts and whether its fire is ready, the fruit eaten,
/// a hint when the sky reaches a harder stage, and a word when something happens (a banana spat out, a poisoned
/// fruit eaten, the dragon exhausted). Hidden in SwiftUI outside the feast (its attachment entity is never
/// disabled).
private struct FeastTallyView: View {
    @Environment(StoryViewModel.self) private var story
    /// A word for a moment after something happens.
    @State private var flash: String?
    /// The current stage's hint, for its first seconds.
    @State private var hint: String?

    private var feast: FeastProgress { story.feast }

    var body: some View {
        VStack(spacing: 8) {
            if story.step == .feast {
                HStack(spacing: 18) {
                    HStack(spacing: 4) {
                        ForEach(0..<feast.maxHearts, id: \.self) { index in
                            Image(systemName: index < feast.hearts ? "heart.fill" : "heart")
                                .foregroundStyle(index < feast.hearts ? .red : .secondary)
                        }
                    }
                    .accessibilityLabel("\(feast.hearts) of \(feast.maxHearts) hearts")
                    // The flame shows whether the fire is ready; pressed, it breathes fire like a snap (the way to do
                    // it without hand tracking).
                    Button {
                        story.requestFire()
                    } label: {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(feast.isFireReady ? .orange : .secondary)
                            .opacity(feast.isFireReady ? 1 : 0.4)
                    }
                    .buttonStyle(.plain)
                    .disabled(!feast.isFireReady)
                    .accessibilityLabel(feast.isFireReady ? "Breathe fire" : "Fire recharging")
                    Label {
                        Text("\(feast.eaten)/\(feast.goal)")
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "leaf.fill")
                    }
                }
                .font(.title2.bold())
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .glassBackgroundEffect()
                .contentTransition(.numericText())
                .transition(.opacity)
                if let message = phaseMessage ?? flash ?? hint {
                    Text(message)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)
                        .shadow(color: .black.opacity(0.6), radius: 6)
                        .transition(.scale.combined(with: .opacity))
                        .id(message)
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: story.step)
        .animation(.spring(duration: 0.3), value: feast)
        .animation(.spring(duration: 0.3), value: flash)
        .animation(.easeInOut(duration: 0.4), value: hint)
        .task(id: feast.bananas) { await show(feast.bananas > 0 ? "Yuck! No bananas." : nil) }
        .task(id: feast.poisoned) {
            await show(feast.poisoned > 0 ? "Poisoned! The dragon lost a heart." : nil)
        }
        // Each stage's hint, the first one too (when the feast begins).
        .task(id: StageHintKey(isFeeding: story.step == .feast, stage: feast.stage)) {
            guard story.step == .feast else { return }
            hint = Self.hint(stage: feast.stage)
            try? await Task.sleep(for: .seconds(6))
            hint = nil
        }
        .accessibilityElement(children: .combine)
    }

    /// What the whole feast is doing, when it is not just playing.
    private var phaseMessage: String? {
        switch feast.phase {
        case .playing: nil
        case .exhausted: "The dragon is exhausted: it lost some fruit. It rests, then flies on."
        case .finished: "The dragon is full!"
        }
    }

    /// What each stage of the sky brings.
    private static func hint(stage: Int) -> String {
        switch stage {
        case 0: "Fly into the fruit to feed the dragon. Push the horns forward to fly faster."
        case 1: "Bananas! The dragon spits them out: don't waste your time."
        case 2: "Poisoned fruit! Avoid them, or let go of a horn and snap your fingers to breathe fire."
        default: "The last stretch: the fruit dodge and less help aiming. Keep the poison away!"
        }
    }

    private struct StageHintKey: Hashable {
        let isFeeding: Bool
        let stage: Int
    }

    private func show(_ message: String?) async {
        guard let message else { return }
        flash = message
        try? await Task.sleep(for: .seconds(2))
        if flash == message { flash = nil }
    }
}

#Preview(immersionStyle: .full) {
    DragonRideView()
        .environment(UntangleViewModel())
        .environment(OrchardViewModel())
        .environment(StoryViewModel())
}
#endif
