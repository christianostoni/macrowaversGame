import Foundation
import RealityKit
import simd

/// The island's grab bar: a pill on the floor in front of the island, like a window's bar. Pinching it and
/// moving the hand carries the island across the room (`IslandPlacement.carried`); the rock still spins it.
/// It lives outside the island's root: it neither turns nor bobs with it, it always faces the player.
struct IslandGrabberComponent: Component {
    let untangle: UntangleViewModel
    let viewer: ViewerTracker
}

/// A carry in progress: the island, the pinching hand (scene) and the player's eyes when it began.
struct IslandCarry {
    let start: IslandPlacement
    let hand: SIMD3<Float>
    let viewer: SIMD3<Float>

    /// Where the island goes with the hand at `hand` now.
    func placement(handAt hand: SIMD3<Float>) -> IslandPlacement {
        start.carried(from: self.hand, to: hand, viewer: viewer)
    }
}

/// Keeps the grab bar in front of the island, on the player's side, turned towards their eyes.
struct IslandGrabberSystem: System {
    static let query = EntityQuery(where: .has(IslandGrabberComponent.self))

    init(scene: RealityKit.Scene) {}

    @MainActor
    static func registerAll() {
        IslandGrabberComponent.registerComponent()
        registerSystem()
    }

    func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard let grabber = entity.components[IslandGrabberComponent.self] else { continue }
            let placement = grabber.untangle.islandPlacement
            let eyes = grabber.viewer.viewerPosition()
            let position = IslandGrabberBuilder.spot(for: placement, viewer: eyes)
            entity.look(at: eyes, from: position, relativeTo: nil, forward: .positiveZ)
        }
    }
}

enum IslandGrabberBuilder {
    static let name = "IslandGrabber"
    /// The pill, at about the size of a window's bar seen from 1.5 m (m).
    static let barSize = SIMD2<Float>(0.24, 0.028)
    /// The pinch area around it: bigger than the pill, so it is easy to catch with the eyes.
    static let targetSize = SIMD3<Float>(0.4, 0.14, 0.14)
    /// From the trunk towards the player (island metres, scaled with the island): just past the rock's edge
    /// (~1.25 m), under the floating rocks.
    static let frontDistance: Float = 1.5
    /// Above the floor (m): under the island, as a window's bar is under the window.
    static let height: Float = 0.14

    @MainActor
    static func makeGrabber(untangle: UntangleViewModel, viewer: ViewerTracker) -> Entity {
        let grabber = Entity()
        grabber.name = name
        var material = UnlitMaterial(color: .white)
        material.blending = .transparent(opacity: 0.6)
        let pill = ModelEntity(mesh: .generateBox(width: barSize.x, height: barSize.y, depth: barSize.y,
                                                  cornerRadius: barSize.y / 2),
                               materials: [material])
        grabber.addChild(pill)
        grabber.components.set(CollisionComponent(shapes: [.generateBox(size: targetSize)]))
        grabber.components.set(InputTargetComponent())
        grabber.components.set(HoverEffectComponent())
        grabber.components.set(IslandGrabberComponent(untangle: untangle, viewer: viewer))
        grabber.position = spot(for: untangle.islandPlacement, viewer: viewer.viewerPosition())
        return grabber
    }

    /// Where the bar stands for the island at `placement`, seen from `viewer` (scene space).
    static func spot(for placement: IslandPlacement, viewer: SIMD3<Float>) -> SIMD3<Float> {
        var towardsViewer = SIMD2(viewer.x - placement.position.x, viewer.z - placement.position.z)
        if simd_length(towardsViewer) < 1e-3 { towardsViewer = SIMD2(0, 1) }
        let front = simd_normalize(towardsViewer) * frontDistance * placement.scale
        return SIMD3(placement.position.x + front.x, height, placement.position.z + front.y)
    }
}
