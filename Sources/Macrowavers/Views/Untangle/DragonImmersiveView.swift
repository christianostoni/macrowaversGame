#if os(visionOS)
import RealityKit
import SwiftUI

/// Immersive space in mixed reality: a floating island (the player spins it) with the dragon captive
/// around the tree and fruit on its branches. Every fruit hides an ingredient that joins an orbit around the
/// player: three of them and a snap of the fingers brew the elixir that soothes the dragon: it flies to
/// the player and settles tangled in front of them; untangled, it thanks them and offers to take them along.
/// The story (`StoryViewModel`) frames it: its scroll and the chapter's title in a darkened room before the island fades in,
/// the dragon's words above it once it is free. When the player is ready the room darkens, the island fades and
/// this space hands over to the ride's (`DragonRideView`, full immersion).
struct DragonImmersiveView: View {
    static let spaceID = "DragonSpace"

    /// Side panel: 0.9 m from the player, 50° to the left, a little below a seated player's eyes.
    /// Outside everything that moves: the island (±20°), the dragon's approach (~1 m straight ahead), the knot
    /// and the fruit in front of the player.
    private static let panelDistance: Float = 0.9
    private static let panelAngle: Float = 50 * .pi / 180
    private static let panelHeight: Float = 1.0

    @Environment(UntangleViewModel.self) private var viewModel
    @Environment(OrchardViewModel.self) private var orchard
    @Environment(StoryViewModel.self) private var story
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    /// Rotation of the island and the hand's position (scene) when the current drag started.
    @State private var islandSpinStart: (yaw: Float, location: SIMD3<Float>)?
    /// Rotation of the island when the current two-hand rotation started (nil: not rotating).
    @State private var islandRotateYawStart: Float?
    /// Subscriptions to the grab events on the dragon: they must stay alive as long as the view exists.
    @State private var subscriptions: [EventSubscription] = []
    /// Position of the player's head: the dragon looks at the knight.
    @State private var viewer = ViewerTracker()
    /// The player's hands: chopping the pineapple, snapping the fingers to brew the elixir.
    @State private var hands = HandTracker()
    /// The island, the dragon and the island panel: built at once, added to the scene when the story reveals them.
    @State private var world = HiddenWorld()
    /// The story's music, in the player's ears.
    @State private var music = GameMusic()
    /// The story's scroll, opened and read before the island appears, and its narrator.
    @State private var storyScroll = StoryScroll()
    @State private var narrator = StoryNarrator()

    var body: some View {
        RealityView { content, attachments in
            content.add(music.entity)
            content.add(narrator.entity)
            // The story's scroll, in front of the player until they have read it, the words under it, and the
            // narrator's subtitles, a little below the gaze.
            let scrollHint = attachments.entity(for: ScrollHintView.attachmentID)
            if let scrollHint { content.add(scrollHint) }
            if let subtitles = attachments.entity(for: StorySubtitleView.attachmentID) {
                subtitles.components.set(StorySubtitleComponent(viewer: viewer))
                subtitles.components.set(BillboardComponent())
                content.add(subtitles)
            }
            if let scroll = await ScrollSceneBuilder.makeScroll(scroll: storyScroll, viewer: viewer, hint: scrollHint) {
                content.add(scroll)
            }
            // The island first: the dragon is born already circling its tree, the fruit hangs from it.
            let island = await IslandSceneBuilder.makeIsland(placement: viewModel.islandPlacement)
            let playArea = await DragonSceneBuilder.makePlayArea(viewModel: viewModel, viewer: viewer,
                                                                 orbitAnchor: island.treeAnchor)
            // Focus mode: with a fruit close the island and the dragon fade back; while the dragon is untangled
            // or speaks only the island does. Both start invisible: they fade in when the story reveals them.
            for (entity, part) in [(island.root, SceneFocus.Part.island), (playArea, .dragon)] {
                entity.components.set(FocusDimmingComponent(untangle: viewModel, orchard: orchard, story: story,
                                                            part: part, opacity: 0))
                entity.components.set(OpacityComponent(opacity: 0))
            }
            world.entities = [island.root, island.floorOccluder, playArea]
            // The elixir flies to the dragon's head (node 0).
            let dragonHead = playArea.findEntity(named: "DragonNode0") ?? playArea
            // While a fruit is close, what is behind it (island rock, dragon) must not take the pinch.
            let background = [island.root.findEntity(named: IslandSceneBuilder.rockName)].compactMap { $0 }
                + Self.descendants(of: playArea).filter { $0.components.has(DragonNodeComponent.self) }
            let orchardRoot = await OrchardSceneBuilder.makeOrchard(
                viewModel: orchard, player: .init(viewer: viewer, hands: hands), island: island,
                deliveryTarget: dragonHead, background: background)
            world.entities.append(orchardRoot)
            // Island panel on the left.
            if let islandPanel = attachments.entity(for: IslandControlsView.attachmentID) {
                world.entities.append(Self.placeSidePanel(islandPanel, angle: -Self.panelAngle))
            }
            // The story's words: in front of the player, or above the dragon when it speaks.
            if let storyPanel = attachments.entity(for: StoryPanelView.attachmentID) {
                storyPanel.components.set(StoryPanelComponent(story: story, untangle: viewModel, viewer: viewer,
                                                              playArea: playArea))
                storyPanel.components.set(BillboardComponent())
                content.add(storyPanel)
            }
            // Instructions under the fruit in front of the player.
            // Attachments are never disabled (`isEnabled`): deactivating a SwiftUI-hosting entity while its
            // content changes makes RealityKit abort ("new parent is currently being removed"). The panels hide
            // themselves in SwiftUI instead.
            if let panel = attachments.entity(for: FruitPanelView.attachmentID),
               let stage = orchardRoot.findEntity(named: OrchardSceneBuilder.stageName) {
                panel.position = SIMD3(0, -0.2, 0.02)
                stage.addChild(panel)
            }
            // The elixir's label, under the ingredients' orbit (it follows the player with the orbit).
            if let panel = attachments.entity(for: ElixirPanelView.attachmentID),
               let anchor = orchardRoot.findEntity(named: ElixirRig.hintAnchorName) {
                panel.components.set(BillboardComponent())
                anchor.addChild(panel)
            }
            subscriptions = subscribeToDragonGrabs(content)
            // Everything is built: the launch window's spinner steps aside, the narrator speaks.
            viewModel.isWorldLoaded = true
        } update: { content, _ in
            // Reading `story.step` here re-runs this block when the story moves on.
            if story.step.revealsWorld { world.reveal(in: content) }
            // Reading `placement`/`islandPlacement` here re-runs this block on every change.
            if let island = content.entities.first(where: { $0.name == IslandSceneBuilder.islandName }),
               var turntable = island.components[TurntableComponent.self] {
                turntable.targetYaw = viewModel.islandPlacement.yaw
                island.components.set(turntable)
            }
            let placement = viewModel.placement
            guard let playArea = content.entities.first(where: { $0.name == DragonSceneBuilder.playAreaName }) else { return }
            playArea.position = placement.position
            playArea.orientation = placement.rotation
        }
        attachments: {
            Attachment(id: StoryPanelView.attachmentID) {
                StoryPanelView()
                    .environment(story)
            }
            Attachment(id: ScrollHintView.attachmentID) {
                ScrollHintView(scroll: storyScroll)
            }
            Attachment(id: StorySubtitleView.attachmentID) {
                StorySubtitleView(scroll: storyScroll)
            }
            Attachment(id: FruitPanelView.attachmentID) {
                FruitPanelView()
                    .environment(orchard)
            }
            Attachment(id: ElixirPanelView.attachmentID) {
                ElixirPanelView()
                    .environment(orchard)
            }
            Attachment(id: IslandControlsView.attachmentID) {
                IslandControlsView()
                    .environment(viewModel)
                    .environment(orchard)
                    .environment(story)
            }
        }
        .gesture(tapDragonGesture)
        .orchardInteractions()
        .simultaneousGesture(spinIslandGesture)
        .simultaneousGesture(rotateIslandGesture)
        .simultaneousGesture(scrollDragGesture)
        .simultaneousGesture(scrollTapGesture)
        // The narrator's pages and the dragon's words darken the room (passthrough) around them.
        // So does the way to the ride.
        .preferredSurroundingsEffect(story.step.dimsSurroundings || story.step.isFullyImmersed ? .dark : nil)
        // The player is ready: the room darkens and the island fades, then the ride's space takes over.
        .onChange(of: story.step.isFullyImmersed) { _, isFullyImmersed in
            guard isFullyImmersed else { return }
            Task { await handOverToRide() }
        }
        // The story reaches its scroll: it appears; read (or skipped), the story goes on to the chapter's title.
        .onChange(of: story.step, initial: true) { _, step in
            if step == .scroll {
                if storyScroll.phase == .hidden { storyScroll.present() }
            } else if storyScroll.phase != .done {
                storyScroll.reset()
            }
        }
        .onChange(of: storyScroll.isDone) { _, isDone in
            if isDone, story.step == .scroll { story.advance() }
        }
        // The narrator tells the story while the scroll is open; the music steps back under the voice.
        .onChange(of: storyScroll.isNarrating) { _, isNarrating in
            if isNarrating { narrator.play() } else { narrator.stop() }
            music.duck(isNarrating)
        }
        .onChange(of: viewModel.isSolved) { _, isSolved in
            // Free, the dragon speaks; back around the tree (Restart Scene), its words are still to come.
            if isSolved { story.dragonFreed() } else { story.dragonRecaptured() }
        }
        // The music follows the story and steps back while the dragon roars.
        .onChange(of: MusicTrack.playing(story: story.step, dragon: viewModel.phase), initial: true) { _, track in
            music.play(track)
        }
        .onChange(of: viewModel.action == .rearUp) { _, roars in music.duck(roars) }
        .task { await music.load() }
        .task { await narrator.load() }
        .task { await viewer.start() }
        .task {
            orchard.isHandTrackingAvailable = await hands.start()
            await hands.track()
        }
        .onAppear { viewModel.immersiveSpaceState = .open }
        .onDisappear {
            viewer.stop()
            hands.stop()
            // Handed over to the ride: the story goes on there.
            guard !story.step.isFullyImmersed else { return }
            // Closed from the island panel or by the system (Digital Crown): start over from the launch window.
            viewModel.resetGame()
            orchard.reset()
            story.reset()
            viewModel.immersiveSpaceState = .closed
            openWindow(id: ContentView.windowID)
        }
    }

    // MARK: - Ride

    /// How long the room stays dark, with the island fading, before the ride's space opens (s).
    private static let rideHandOverDelay: Duration = .seconds(1.2)

    /// Closes this space and opens the ride's (only one immersive space can be open at a time).
    private func handOverToRide() async {
        try? await Task.sleep(for: Self.rideHandOverDelay)
        guard story.step.isFullyImmersed, viewModel.immersiveSpaceState == .open else { return }
        viewModel.immersiveSpaceState = .inTransition
        await dismissImmersiveSpace()
        switch await openImmersiveSpace(id: DragonRideView.spaceID) {
        case .opened:
            break
        default:
            // No ride: back to the launch window, as when the space closes.
            viewModel.resetGame()
            orchard.reset()
            story.reset()
            viewModel.immersiveSpaceState = .closed
            openWindow(id: ContentView.windowID)
        }
    }

    // MARK: - Story scroll

    /// Pull the closed scroll down to open it, then drag its paper up and down to read.
    private var scrollDragGesture: some Gesture {
        DragGesture()
            .targetedToEntity(where: .has(ScrollHandleComponent.self))
            .onChanged { value in
                storyScroll.drag(height: value.convert(value.location3D, from: .local, to: .scene).y)
            }
            .onEnded { _ in
                storyScroll.endDrag()
            }
    }

    /// Pinch the closed scroll: it opens by itself (also the way to open it in the simulator).
    private var scrollTapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToEntity(where: .has(ScrollHandleComponent.self))
            .onEnded { _ in
                storyScroll.tap()
            }
    }

    // MARK: - Dragon

    /// Look at the dragon circling the tree and pinch: it gets angry.
    /// Only the colliders with `DragonTapTargetComponent` answer (that is, only while it is on the island).
    private var tapDragonGesture: some Gesture {
        SpatialTapGesture()
            .targetedToEntity(where: .has(DragonTapTargetComponent.self))
            .onEnded { _ in
                viewModel.tapDragon()
            }
    }

    private static func descendants(of entity: Entity) -> [Entity] {
        entity.children.flatMap { [$0] + descendants(of: $0) }
    }

    /// Puts a panel to the side of the player, turned towards them (it keeps facing them as they move).
    private static func placeSidePanel(_ panel: Entity, angle: Float) -> Entity {
        panel.position = SIMD3(panelDistance * sin(angle), panelHeight, -panelDistance * cos(angle))
        panel.components.set(BillboardComponent())
        return panel
    }

    // MARK: - Island

    /// Drag the island's rock: it spins like a turntable around the trunk, its side facing the player following
    /// the hand (see `IslandPlacement.spinAngle`).
    private var spinIslandGesture: some Gesture {
        DragGesture()
            .targetedToEntity(where: .has(IslandHandleComponent.self))
            .onChanged { value in
                let location = value.convert(value.location3D, from: .local, to: .scene)
                // Both hands rotating: the two-hand gesture drives the island. The drag goes on from here afterwards.
                guard islandRotateYawStart == nil else {
                    islandSpinStart = (yaw: viewModel.islandPlacement.yaw, location: location)
                    return
                }
                let start = islandSpinStart
                    ?? (yaw: viewModel.islandPlacement.yaw,
                        location: value.convert(value.startLocation3D, from: .local, to: .scene))
                islandSpinStart = start
                let turn = viewModel.islandPlacement.spinAngle(handMovement: location - start.location,
                                                               viewer: viewer.viewerPosition())
                viewModel.setIslandYaw(start.yaw + turn)
            }
            .onEnded { _ in
                islandSpinStart = nil
            }
    }

    /// Rotate the island with two hands (in the simulator: hold Option).
    private var rotateIslandGesture: some Gesture {
        RotateGesture3D(constrainedToAxis: .y)
            .targetedToEntity(where: .has(IslandHandleComponent.self))
            .onChanged { value in
                let start = islandRotateYawStart ?? viewModel.islandPlacement.yaw
                islandRotateYawStart = start
                let quaternion = value.rotation.quaternion
                let angle = Float(2 * atan2(quaternion.imag.y, quaternion.real))
                // SwiftUI space has y pointing down: opposite sign to RealityKit.
                viewModel.setIslandYaw(start - angle)
            }
            .onEnded { _ in
                islandRotateYawStart = nil
            }
    }

    /// Each node of the dragon has its own `ManipulationComponent`: each hand grabs and moves its own node,
    /// so the left and the right hand hold two parts of the body at the same time, independently.
    /// Here the view model hears which hand starts, passes on and lets go of which node (`HandGrabs` sorts out
    /// the events); the movement is read by the `DragonBodySystem`.
    private func subscribeToDragonGrabs(_ content: RealityViewContent) -> [EventSubscription] {
        [
            content.subscribe(to: ManipulationEvents.WillBegin.self) { event in
                guard let node = event.entity.components[DragonNodeComponent.self] else { return }
                viewModel.manipulationBegan(node: node.index, hands: Self.hands(event.inputDeviceSet))
            },
            content.subscribe(to: ManipulationEvents.DidHandOff.self) { event in
                guard let node = event.entity.components[DragonNodeComponent.self] else { return }
                viewModel.manipulationHandedOff(node: node.index, to: Self.hands(event.newInputDeviceSet))
            },
            content.subscribe(to: ManipulationEvents.WillRelease.self) { event in
                guard let node = event.entity.components[DragonNodeComponent.self] else { return }
                viewModel.manipulationReleased(node: node.index)
            },
            // A grab that ends without a release (cancelled) still frees the node.
            content.subscribe(to: ManipulationEvents.WillEnd.self) { event in
                guard let node = event.entity.components[DragonNodeComponent.self] else { return }
                viewModel.manipulationEnded(node: node.index)
            },
        ]
    }

    private static func hands(_ devices: ManipulationEvents.InputDeviceSet) -> Set<HandGrabs.Hand> {
        Set(devices.map { device in
            switch device.chirality {
            case .left: .left
            case .right: .right
            case nil: .unknown
            @unknown default: .unknown
            }
        })
    }
}

/// What the story keeps out of the room until the chapter's title has been read: the island, its fruit, the
/// dragon and the side panels. Added to the scene once (never disabled: attachments must not be).
@MainActor
final class HiddenWorld {
    var entities: [Entity] = []
    private(set) var isRevealed = false

    func reveal(in content: RealityViewContent) {
        guard !isRevealed, !entities.isEmpty else { return }
        isRevealed = true
        entities.forEach { content.add($0) }
    }
}

#Preview(immersionStyle: .mixed) {
    let story = StoryViewModel()
    story.begin()
    return DragonImmersiveView()
        .environment(UntangleViewModel())
        .environment(OrchardViewModel())
        .environment(story)
}
#endif
