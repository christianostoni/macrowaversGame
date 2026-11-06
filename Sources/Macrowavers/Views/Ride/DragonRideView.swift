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
    private static let messagesID = "FeastMessages"
    private static let hintID = "HornsHint"
    private static let loadingID = "RideLoading"
    private static let titleID = "RideTitle"
    /// The loading animation and chapter II's name: their distance in front of the eyes (m).
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
    /// The ride's world is built (the dragon, the sky, the fruit): the loading animation gives way to chapter II's
    /// name.
    @State private var isLoaded = false
    /// The ride's world once built (`update` adds it to the scene).
    @State private var ride: Entity?
    /// The ride's music, in the player's ears (the island's closed with its space).
    @State private var music = GameMusic()

    var body: some View {
        // `make` returns at once: nothing it adds shows before it returns, so building the ride in it kept the
        // loading animation from ever being seen. The ride is built in a task and added by `update`.
        RealityView { content, attachments in
            content.add(music.entity)
            // The loading animation in the dark while the ride's assets load, placed once in front of the eyes.
            if let loading = attachments.entity(for: Self.loadingID) {
                let anchor = AnchorEntity(.head, trackingMode: .once)
                loading.position = SIMD3(0, 0, -Self.loadingDistance)
                anchor.addChild(loading)
                content.add(anchor)
            }
        } update: { content, attachments in
            // Chapter II's name once the ride is built, in front of the eyes where they are then: in the world, not
            // on a head anchor, so it takes the tap that starts the ride.
            if isLoaded, let title = attachments.entity(for: Self.titleID), title.parent == nil {
                content.add(Self.inFrontOfEyes(title, viewer: viewer))
            }
            guard let ride, ride.parent == nil else { return }
            content.add(ride)
            // Chapter II's goal, the feast's words and how to hold the horns ride along, in front of the eyes.
            for (id, spot) in [(StoryPanelView.attachmentID, DragonRideSceneBuilder.panelSpot),
                               (Self.messagesID, DragonRideSceneBuilder.tallySpot),
                               (Self.hintID, DragonRideSceneBuilder.hintSpot)] {
                guard let attachment = attachments.entity(for: id) else { continue }
                attachment.position = spot
                // Drawn after the ride's see-through sky (the shamseh's glass, the lanterns, the clouds), in their
                // sort group: outside it they fell behind the medallion.
                ride.addChild(attachment)
            }
        } attachments: {
            Attachment(id: StoryPanelView.attachmentID) {
                StoryPanelView(hasBackdrop: true)
            }
            Attachment(id: Self.messagesID) {
                FeastMessagesView()
            }
            Attachment(id: Self.hintID) {
                HornsHintView(status: status)
            }
            Attachment(id: Self.loadingID) {
                RideLoadingView(isLoaded: isLoaded)
            }
            Attachment(id: Self.titleID) {
                RideTitleView(isLoaded: isLoaded, status: status)
            }
        }
        // Without hand tracking, a tap on the sky breathes fire (the snap's alternative).
        .gesture(SpatialTapGesture().targetedToEntity(where: .has(RideFireTarget.self)).onEnded { _ in
            story.requestFire()
        })
        // The music fades in out of the dark, follows the story and fades out as the space closes.
        .onChange(of: MusicTrack.riding(story: story.step), initial: true) { _, track in
            music.play(track)
        }
        // The ride's world, built while the loading animation plays (without the dragon, no ride: the space just
        // waits for the Digital Crown).
        .task {
            guard ride == nil, !isLoaded else { return }
            let built = await DragonRideSceneBuilder.makeRide(story: story, status: status, viewer: viewer,
                                                              hands: hands)
            ride = built
            isLoaded = true
            if built == nil { status.isChapterOpened = true }
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
        #if DEBUG
        // `-StorySkipsChapterTitle`: the ride sets off as soon as it is built.
        .onChange(of: isLoaded) { _, isLoaded in
            if isLoaded && StoryViewModel.skipsChapterTitle { status.isChapterOpened = true }
        }
        #endif
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

    /// `entity` in the world `loadingDistance` in front of the player's eyes, level, facing them (the room's
    /// default eye height without head tracking).
    private static func inFrontOfEyes(_ entity: Entity, viewer: ViewerTracker) -> Entity {
        let (eyes, forward) = viewer.viewerPose()
        let holder = Entity()
        holder.transform = Transform(rotation: simd_quatf(angle: atan2(-forward.x, -forward.z), axis: SIMD3(0, 1, 0)),
                                     translation: eyes)
        entity.position = SIMD3(0, 0, -loadingDistance)
        holder.addChild(entity)
        return holder
    }
}

/// The ride's loading animation in the dark while its world is built (`DragonLoadingView`), as the launch window
/// shows it while the island is built. Hidden in SwiftUI once built (its attachment entity is never disabled).
private struct RideLoadingView: View {
    let isLoaded: Bool

    var body: some View {
        ZStack {
            if !isLoaded {
                VStack(spacing: 12) {
                    DragonLoadingView()
                    Text("Loading…")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(32)
                .glassBackgroundEffect()
                .transition(.opacity)
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: isLoaded)
    }
}

/// Chapter II's name (`StoryStep.rideTitle`) once the ride's world is built, as chapter I's title opens the island:
/// tapped (look at it and pinch), it goes and the ride sets off out of the dark. Hidden in SwiftUI (its attachment
/// entity is never disabled).
private struct RideTitleView: View {
    let isLoaded: Bool
    let status: RideStatus

    var body: some View {
        ZStack {
            if isLoaded && !status.isChapterOpened {
                Button {
                    status.isChapterOpened = true
                } label: {
                    StoryPageCard(page: StoryStep.rideTitle, isChapter: true) {
                        Label("Tap to continue", systemImage: "hand.tap")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .contentShape(.hoverEffect, .rect(cornerRadius: StoryPageCardStyle.cornerRadius))
                .hoverEffect(.highlight)
                .accessibilityHint("Begins chapter II")
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: isLoaded)
        .animation(.easeInOut(duration: 0.6), value: status.isChapterOpened)
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
                    Text("Ride the dragon by the horns")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                    Text("Raise or lower your arms to climb or dive.\nMove them to a side to turn.")
                        .font(.body.weight(.medium))
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

/// Chapter II's words while the player feeds the dragon, over its head: a hint when the sky reaches a harder stage,
/// and a word when something happens (a banana spat out, a poisoned fruit eaten, the feast lost or won). No bar:
/// the medallion in the sky shows how far the feast has come. Hidden in SwiftUI outside the feast (its attachment
/// entity is never disabled).
private struct FeastMessagesView: View {
    @Environment(StoryViewModel.self) private var story
    /// A word for a moment after something happens.
    @State private var flash: String?
    /// The current stage's hint, for its first seconds.
    @State private var hint: String?

    private var feast: FeastProgress { story.feast }

    var body: some View {
        ZStack {
            if story.step == .feast, let message = phaseMessage ?? flash ?? hint {
                Text(message)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
                    .shadow(color: .black.opacity(0.6), radius: 6)
                    .transition(.scale.combined(with: .opacity))
                    .id(message)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: story.step)
        .animation(.spring(duration: 0.3), value: flash)
        .animation(.easeInOut(duration: 0.4), value: hint)
        .animation(.easeInOut(duration: 0.4), value: feast.phase)
        .task(id: feast.bananas) { await show(feast.bananas > 0 ? "Yuck! No bananas." : nil) }
        .task(id: feast.poisoned) {
            await show(feast.poisoned > 0 ? "Poisoned! The shamseh lost two pieces of glass." : nil)
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
        case .failed: "The poison shattered the shamseh!"
        case .finished: "The dragon is full! Congrats"
        }
    }

    /// What each stage of the sky brings.
    private static func hint(stage: Int) -> String {
        switch stage {
        case 0: "Eat the fruits. Push the horns forward to fly faster."
        case 1: "No Bananas! The dragon spits them: don't waste your time."
        case 2: "Poisoned fruit break two pieces of the shamseh! Avoid them, or snap your fingers to destroy them."
        default: "The last: the fruits are running away!"
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
