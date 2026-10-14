import Foundation
import RealityKit
import simd

/// Slow up-and-down float (island, floating rocks, fruit, pomegranate seeds): depth and life without
/// distraction. Island and rocks have different periods, so they move relative to each other (parallax).
struct FloatingComponent: Component {
    /// Rest position, in the parent's space.
    var base: SIMD3<Float>
    /// "Up" direction in the parent's space (the asset may have a rotation on its root).
    var axis: SIMD3<Float> = SIMD3(0, 1, 0)
    /// Amplitude in the parent's space.
    var amplitude: Float
    var period: Float
    var phase: Float = 0
    var time: Float = 0
    /// Holds still at `base` (e.g. a seed held in the hand).
    var isPaused = false
}

struct FloatingSystem: System {
    static let query = EntityQuery(where: .has(FloatingComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let deltaTime = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var floating = entity.components[FloatingComponent.self] else { continue }
            floating.time += deltaTime
            let offset = floating.isPaused ? 0 : floating.amplitude * sin(2 * .pi * floating.time / floating.period + floating.phase)
            entity.position = floating.base + floating.axis * offset
            entity.components.set(floating)
        }
    }
}

/// Marks the island's rock: dragging it (or rotating it with two hands) spins the island like a turntable.
struct IslandHandleComponent: Component {}

/// Rotation of the island around the trunk, with inertia: the angle follows `targetYaw` (set by the view
/// model) without jumps, even when it comes in steps from the panel buttons.
struct TurntableComponent: Component {
    var targetYaw: Float
    var yaw: Float
    /// How fast it reaches the wanted angle (1/s).
    var responsiveness: Float = 6
}

struct TurntableSystem: System {
    static let query = EntityQuery(where: .has(TurntableComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let deltaTime = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var turntable = entity.components[TurntableComponent.self] else { continue }
            // Difference along the shortest arc (from 170° to -170° is 20°, not 340°).
            let difference = turntable.targetYaw - turntable.yaw
            let shortest = atan2(sin(difference), cos(difference))
            guard abs(shortest) > 1e-4 else { continue }
            turntable.yaw += shortest * (1 - exp(-deltaTime * turntable.responsiveness))
            entity.orientation = simd_quatf(angle: turntable.yaw, axis: SIMD3(0, 1, 0))
            entity.components.set(turntable)
        }
    }
}

/// Builds the floating island with the tree at its centre: the dragon circles it, the fruit hangs from it.
enum IslandSceneBuilder {
    static let islandName = "FloatingIsland"
    static let treeAnchorName = "TreeAnchor"
    static let rockName = "IslandRock"

    struct Island {
        let root: Entity
        /// Base of the trunk (the asset's origin): centre of the dragon's orbit.
        let treeAnchor: Entity
        /// Fruit centres on the canopy, in the root's space (asset metres).
        let fruitHangPoints: [SIMD3<Float>]
    }

    /// If the asset is missing the anchor still exists: the dragon circles an empty spot and the fruit hangs
    /// on a ring where the canopy would be.
    @MainActor
    static func makeIsland(placement: IslandPlacement) async -> Island {
        let root = Entity()
        root.name = islandName
        root.position = placement.position
        root.orientation = placement.rotation
        root.scale = SIMD3(repeating: placement.scale)
        root.components.set(FloatingComponent(base: placement.position, amplitude: 0.02, period: 7))
        root.components.set(TurntableComponent(targetYaw: placement.yaw, yaw: placement.yaw))

        // The rock is the handle that spins the island; the model is its child so the whole island lights up
        // when the player looks at the rock. The fruit hangs from the root: it gets its own highlight.
        let rock = Entity()
        rock.name = rockName
        root.addChild(rock)

        var rockBounds = BoundingBox(min: SIMD3(-1.25, -1.3, -1.25), max: SIMD3(1.25, 0, 1.25))
        var hangPoints: [SIMD3<Float>] = []
        do {
            let model = try await Entity(named: islandName, in: .main)
            rock.addChild(model)
            if let island = model.findEntity(named: "Island") {
                rockBounds = island.visualBounds(relativeTo: root)
            }
            // The floating rocks bob on their own, faster than the island.
            if let rocks = model.findEntity(named: "FloatingRocks"), let parent = rocks.parent {
                let up = parent.convert(direction: SIMD3(0, 1, 0), from: root)
                rocks.components.set(FloatingComponent(base: rocks.position, axis: simd_normalize(up),
                                                       amplitude: 0.05 * simd_length(up), period: 4.5, phase: 1.3))
            }
            // Hang points made by make_island_asset.py (`fruit_01`, `fruit_02`, ...).
            hangPoints = (1...12).compactMap { index in
                model.findEntity(named: String(format: "fruit_%02d", index))?.position(relativeTo: root)
            }
        } catch {
            print("⚠️ \(islandName).usdz not found: the dragon circles an empty spot (\(error))")
        }
        if hangPoints.isEmpty {
            hangPoints = (0..<6).map { index in
                let angle = Float(index) / 6 * 2 * .pi
                return SIMD3(0.75 * cos(angle), 0.8 + 0.08 * Float(index % 2), 0.75 * sin(angle))
            }
        }

        // Collider only below the ground (the rock): the dragon circling above stays tappable.
        let top: Float = -0.02
        let size = SIMD3(rockBounds.extents.x, max(top - rockBounds.min.y, 0.1), rockBounds.extents.z)
        let shape = ShapeResource.generateBox(size: size)
            .offsetBy(translation: SIMD3(rockBounds.center.x, top - size.y / 2, rockBounds.center.z))
        rock.components.set(CollisionComponent(shapes: [shape]))
        rock.components.set(InputTargetComponent())
        rock.components.set(HoverEffectComponent())
        rock.components.set(IslandHandleComponent())

        let treeAnchor = Entity()
        treeAnchor.name = treeAnchorName
        root.addChild(treeAnchor)
        return Island(root: root, treeAnchor: treeAnchor, fruitHangPoints: hangPoints)
    }
}
