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

    @Environment(UntangleViewModel.self) private var viewModel
    @Environment(OrchardViewModel.self) private var orchard
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
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
            let orchardRoot = await OrchardSceneBuilder.makeOrchard(
                viewModel: orchard, viewer: viewer, island: island, deliveryTarget: dragonHead)
            content.add(orchardRoot)
            // Instructions under the fruit in front of the player.
            if let panel = attachments.entity(for: FruitPanelView.attachmentID),
               let stage = orchardRoot.findEntity(named: OrchardSceneBuilder.stageName) {
                panel.position = SIMD3(0, -0.2, 0.02)
                panel.isEnabled = false
                stage.addChild(panel)
            }
            subscriptions = subscribeToDragonGrabs(content)
        } update: { content, attachments in
            attachments.entity(for: FruitPanelView.attachmentID)?.isEnabled = orchard.focusedFruitID != nil
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
        }
        .gesture(tapDragonGesture)
        .orchardInteractions()
        .simultaneousGesture(spinIslandGesture)
        .simultaneousGesture(rotateIslandGesture)
        .task { await viewer.start() }
        .onAppear { viewModel.immersiveSpaceState = .open }
        .onDisappear {
            // Closed from the panel or by the system (Digital Crown): no orphan windows, start over.
            viewer.stop()
            dismissWindow(id: DragonPanelView.windowID)
            viewModel.resetGame()
            orchard.reset()
            viewModel.immersiveSpaceState = .closed
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
                // Single-instance `Window`: if it is already open it comes to the front, it is never duplicated.
                openWindow(id: DragonPanelView.windowID)
            }
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
