#if os(visionOS)
import RealityKit
import SwiftUI

/// The story's last part, in its own full immersive space (the game's space hands over to it): the player rides on
/// the dragon's back out of the dark into the sky, steering it with both hands (`DragonRideSystem`), the air rushing
/// past; then chapter II, feeding the dragon wave after wave of fruit floating in the sky (not the bananas, not the
/// poisoned ones: a snap of the fingers breathes fire on them), until it is full and flies into the star medallion
/// they lit up, where the story ends. "The End" (or the Digital Crown) closes it: the story starts over from the
/// launch window.
struct DragonRideView: View {
    static let spaceID = "DragonRideSpace"
    private static let tallyID = "FeastTally"
    private static let hintID = "HornsHint"

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

    var body: some View {
        RealityView { content, attachments in
            guard let ride = await DragonRideSceneBuilder.makeRide(story: story, status: status, viewer: viewer,
                                                                    hands: hands) else {
                return
            }
            content.add(ride)
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
        }
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

/// Chapter II's tally while the player feeds the dragon: its hearts and whether its fire is ready, the wave and the
/// fruit eaten in it, a hint at the start of each wave, and a word when something happens (a banana spat out, a
/// poisoned fruit eaten, the dragon exhausted, a wave cleared). Hidden in SwiftUI outside the feast (its attachment
/// entity is never disabled).
private struct FeastTallyView: View {
    @Environment(StoryViewModel.self) private var story
    /// A word for a moment after something happens.
    @State private var flash: String?
    /// The current wave's hint, for its first seconds.
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
                        Text("Wave \(feast.wave + 1)/\(feast.waveCount) · \(feast.eaten)/\(feast.goal)")
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
        // Each wave's hint, the first one too (when the feast begins).
        .task(id: WaveHintKey(isFeeding: story.step == .feast, wave: feast.wave)) {
            guard story.step == .feast else { return }
            hint = Self.hint(wave: feast.wave)
            try? await Task.sleep(for: .seconds(6))
            hint = nil
        }
        .accessibilityElement(children: .combine)
    }

    /// What the whole feast is doing, when it is not just playing.
    private var phaseMessage: String? {
        switch feast.phase {
        case .playing: nil
        case .waveCleared: "Wave cleared! Get ready…"
        case .exhausted: "The dragon is exhausted. It rests, then tries again."
        case .finished: "The dragon is full!"
        }
    }

    /// What each wave brings.
    private static func hint(wave: Int) -> String {
        switch wave {
        case 0: "Fly into the fruit to feed the dragon. Push the horns forward to fly faster."
        case 1: "Bananas! The dragon spits them out: don't waste your time."
        case 2: "Poisoned fruit! Avoid them, or let go of a horn and snap your fingers to breathe fire."
        default: "The last stretch: less help aiming. Keep the poison away!"
        }
    }

    private struct WaveHintKey: Hashable {
        let isFeeding: Bool
        let wave: Int
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
