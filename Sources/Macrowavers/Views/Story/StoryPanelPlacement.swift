import Foundation
import RealityKit
import simd

/// Where the story's page floats (see `StoryStep.Anchor`):
/// - the narrator's pages in front of the player's eyes, world-locked; when the player looks away they glide
///   back in front of them (lazy follow), never stuck to the head;
/// - the dragon's words just above its body, following it as it breathes.
/// The entity also has a `BillboardComponent`, so the text always faces the player.
struct StoryPanelComponent: Component {
    let story: StoryViewModel
    let untangle: UntangleViewModel
    let viewer: ViewerTracker
    /// The dragon's space (its nodes are in this entity's space).
    let playArea: Entity
    /// Anchor the page is placed for: a new one moves the page there at once (it fades in), the same one
    /// keeps it where it is, so consecutive pages do not jump.
    var placedAnchor: StoryStep.Anchor?
    /// Where the narrator's page rests, in scene space.
    var viewerSpot: SIMD3<Float> = .zero

    /// The narrator's page: this far in front of the eyes and a little below them.
    static let viewerDistance: Float = 1.3
    static let viewerDrop: Float = 0.08
    /// Looking further away than this from the page brings it back in front of the eyes.
    static let lookAwayAngle: Float = 35 * .pi / 180
    /// The page also comes back when the eyes move this far from where it expects them (the player stands
    /// up or walks; the first frames, before head tracking starts, assume a seated player).
    static let driftTolerance: Float = 0.3
    /// Gap between the top of the dragon's body and the centre of its words.
    static let dragonClearance: Float = 0.2
    /// How fast the page glides to its spot (1/s).
    static let responsiveness: Float = 3
}

struct StoryPanelSystem: System {
    static let query = EntityQuery(where: .has(StoryPanelComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let deltaTime = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var panel = entity.components[StoryPanelComponent.self] else { continue }
            guard let anchor = panel.story.step.page?.anchor else {
                if panel.placedAnchor != nil {
                    panel.placedAnchor = nil
                    entity.components.set(panel)
                }
                continue
            }
            let isNew = panel.placedAnchor != anchor
            let target: SIMD3<Float> = switch anchor {
            case .viewer: Self.viewerSpot(for: &panel, recentre: isNew)
            case .dragon: Self.dragonSpot(for: panel)
            }
            let current = entity.position(relativeTo: nil)
            let next = isNew ? target : current + (target - current) * (1 - exp(-deltaTime * StoryPanelComponent.responsiveness))
            if simd_distance(next, current) > 0.0005 { entity.setPosition(next, relativeTo: nil) }
            if isNew { panel.placedAnchor = anchor }
            entity.components.set(panel)
        }
    }

    /// In front of the eyes; moved there again when the player looks too far away from it or moves.
    @MainActor
    private static func viewerSpot(for panel: inout StoryPanelComponent, recentre: Bool) -> SIMD3<Float> {
        let pose = panel.viewer.viewerPose()
        var forward = SIMD3(pose.forward.x, 0, pose.forward.z)
        forward = simd_length(forward) > 1e-3 ? simd_normalize(forward) : SIMD3(0, 0, -1)
        var toSpot = panel.viewerSpot - pose.position
        toSpot.y = 0
        let isOutOfView = simd_length(toSpot) < 1e-3
            || acos(max(-1, min(1, simd_dot(simd_normalize(toSpot), forward)))) > StoryPanelComponent.lookAwayAngle
        let tolerance = StoryPanelComponent.driftTolerance
        let hasDrifted = abs(panel.viewerSpot.y + StoryPanelComponent.viewerDrop - pose.position.y) > tolerance
            || abs(simd_length(toSpot) - StoryPanelComponent.viewerDistance) > tolerance
        if recentre || isOutOfView || hasDrifted {
            panel.viewerSpot = pose.position + forward * StoryPanelComponent.viewerDistance
                - SIMD3(0, StoryPanelComponent.viewerDrop, 0)
        }
        return panel.viewerSpot
    }

    /// Above the highest point of the dragon's body, over its middle.
    @MainActor
    private static func dragonSpot(for panel: StoryPanelComponent) -> SIMD3<Float> {
        let positions = panel.untangle.displayPositions
        let worldFromDragon = panel.playArea.transformMatrix(relativeTo: nil)
        let points = positions.map { point in
            let world = worldFromDragon * SIMD4(point, 1)
            return SIMD3(world.x, world.y, world.z)
        }
        guard !points.isEmpty else { return panel.playArea.position(relativeTo: nil) }
        let centre = points.reduce(.zero, +) / Float(points.count)
        let top = points.map(\.y).max() ?? centre.y
        return SIMD3(centre.x, top + StoryPanelComponent.dragonClearance, centre.z)
    }
}
