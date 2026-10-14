#if os(visionOS)
import RealityKit
import SwiftUI

/// Immersive space in mixed reality: a floating island (the player spins it) with the dragon captive
/// around the tree and fruit on its branches. The artifact found in an apple soothes the dragon: it flies to
/// the player and settles tangled in front of them; untangled, it flies away into the sky.
struct DragonImmersiveView: View {
    static let spaceID = "DragonSpace"

    /// Turntable: how much the island turns compared to the angle the hand draws around the trunk.
    private static let spinGain: Float = 2
    /// Side panels: 0.9 m from the player, 50° to the left / right, a little below a seated player's eyes.
    /// Outside everything that moves: the island (±20°), the dragon's approach (~1 m straight ahead), the knot
    /// and the fruit in front of the player, the farewell circles (≥ 1.1 m).
    private static let panelDistance: Float = 0.9
    private static let panelAngle: Float = 50 * .pi / 180
    private static let panelHeight: Float = 1.0

    @Environment(UntangleViewModel.self) private var viewModel
    @Environment(OrchardViewModel.self) private var orchard
    @Environment(\.openWindow) private var openWindow
    /// Rotation of the island when the current gesture started.
    @State private var islandYawStart: Float?
    /// Subscriptions to the grab events on the dragon: they must stay alive as long as the view exists.
    @State private var subscriptions: [EventSubscription] = []
    /// Position of the player's head: the dragon looks at the knight.
    @State private var viewer = ViewerTracker()

    var body: some View {
        RealityView { content, attachments in
            // The island first: the dragon is born already circling its tree, the fruit hangs from it.
            let island = await IslandSceneBuilder.makeIsland(placement: viewModel.islandPlacement)
            content.add(island.root)
            let playArea = await DragonSceneBuilder.makePlayArea(viewModel: viewModel, viewer: viewer,
                                                                 orbitAnchor: island.treeAnchor)
            content.add(playArea)
            // The artifact flies to the dragon's head (node 0).
            let dragonHead = playArea.findEntity(named: "DragonNode0") ?? playArea
            // While a fruit is close, what is behind it (island rock, dragon) must not take the pinch.
            let background = [island.root.findEntity(named: IslandSceneBuilder.rockName)].compactMap { $0 }
                + Self.descendants(of: playArea).filter { $0.components.has(DragonNodeComponent.self) }
            let orchardRoot = await OrchardSceneBuilder.makeOrchard(
                viewModel: orchard, viewer: viewer, island: island, deliveryTarget: dragonHead,
                background: background)
            content.add(orchardRoot)
            // Island panel on the left, dragon panel on the right.
            if let islandPanel = attachments.entity(for: IslandControlsView.attachmentID) {
                content.add(Self.placeSidePanel(islandPanel, angle: -Self.panelAngle))
            }
            if let dragonPanel = attachments.entity(for: DragonPanelView.attachmentID) {
                content.add(Self.placeSidePanel(dragonPanel, angle: Self.panelAngle))
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
            subscriptions = subscribeToDragonGrabs(content)
        } update: { content, _ in
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
            Attachment(id: FruitPanelView.attachmentID) {
                FruitPanelView()
                    .environment(orchard)
            }
            Attachment(id: IslandControlsView.attachmentID) {
                IslandControlsView()
                    .environment(viewModel)
                    .environment(orchard)
            }
            Attachment(id: DragonPanelView.attachmentID) {
                DragonPanelView()
                    .environment(viewModel)
                    .environment(orchard)
            }
        }
        .gesture(tapDragonGesture)
        .orchardInteractions()
        .simultaneousGesture(spinIslandGesture)
        .simultaneousGesture(rotateIslandGesture)
        .task { await viewer.start() }
        .onAppear { viewModel.immersiveSpaceState = .open }
        .onDisappear {
            // Closed from the island panel or by the system (Digital Crown): start over from the launch window.
            viewer.stop()
            viewModel.resetGame()
            orchard.reset()
            viewModel.immersiveSpaceState = .closed
            openWindow(id: ContentView.windowID)
        }
    }

    // MARK: - Dragon

    /// Look at the dragon circling the tree and pinch: it gets angry and its panel opens.
    /// Only the colliders with `DragonTapTargetComponent` answer (that is, only while it is on the island).
    private var tapDragonGesture: some Gesture {
        SpatialTapGesture()
            .targetedToEntity(where: .has(DragonTapTargetComponent.self))
            .onEnded { _ in
                viewModel.tapDragon()
                viewModel.isDragonPanelVisible = true
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

    /// Drag the island's rock: it spins like a turntable around the trunk.
    private var spinIslandGesture: some Gesture {
        DragGesture()
            .targetedToEntity(where: .has(IslandHandleComponent.self))
            .onChanged { value in
                let start = islandYawStart ?? viewModel.islandPlacement.yaw
                islandYawStart = start
                let center = viewModel.islandPlacement.position
                let from = value.convert(value.startLocation3D, from: .local, to: .scene)
                let to = value.convert(value.location3D, from: .local, to: .scene)
                // Angle drawn by the hand around the trunk (same direction as a rotation around +Y).
                let turn = atan2(to.x - center.x, to.z - center.z) - atan2(from.x - center.x, from.z - center.z)
                viewModel.setIslandYaw(start + Self.spinGain * atan2(sin(turn), cos(turn)))
            }
            .onEnded { _ in
                islandYawStart = nil
            }
    }

    /// Rotate the island with two hands (in the simulator: hold Option).
    private var rotateIslandGesture: some Gesture {
        RotateGesture3D(constrainedToAxis: .y)
            .targetedToEntity(where: .has(IslandHandleComponent.self))
            .onChanged { value in
                let start = islandYawStart ?? viewModel.islandPlacement.yaw
                islandYawStart = start
                let quaternion = value.rotation.quaternion
                let angle = Float(2 * atan2(quaternion.imag.y, quaternion.real))
                // SwiftUI space has y pointing down: opposite sign to RealityKit.
                viewModel.setIslandYaw(start - angle)
            }
            .onEnded { _ in
                islandYawStart = nil
            }
    }

    /// Each node of the dragon has a `ManipulationComponent`: each hand grabs and moves its own node,
    /// so two parts of the body can be held at the same time.
    /// Here the view model hears when a grab starts/ends; the movement is read by the `DragonBodySystem`.
    private func subscribeToDragonGrabs(_ content: RealityViewContent) -> [EventSubscription] {
        [
            content.subscribe(to: ManipulationEvents.WillBegin.self) { event in
                guard let node = event.entity.components[DragonNodeComponent.self] else { return }
                viewModel.grab(node: node.index)
            },
            content.subscribe(to: ManipulationEvents.WillRelease.self) { event in
                guard let node = event.entity.components[DragonNodeComponent.self] else { return }
                viewModel.release(node: node.index)
            },
            // Safety: if the grab ends without a release (e.g. cancelled), the node must still be freed.
            content.subscribe(to: ManipulationEvents.WillEnd.self) { event in
                guard let node = event.entity.components[DragonNodeComponent.self] else { return }
                viewModel.release(node: node.index)
            },
        ]
    }
}

#Preview(immersionStyle: .mixed) {
    DragonImmersiveView()
        .environment(UntangleViewModel())
        .environment(OrchardViewModel())
}
#endif
