import RealityKit
import simd
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Index of the body's node (vertebra): tells which point was grabbed.
struct DragonNodeComponent: Component {
    let index: Int
}

/// Connects the dragon to the view model. Every frame the `DragonBodySystem` reads where the hands moved
/// the grabbed colliders, advances the game, realigns the other colliders and updates the rig (visuals).
struct DragonBodyComponent: Component {
    let viewModel: UntangleViewModel
    let rig: DragonRig
    let colliders: [Entity]
    let markers: CrossingMarkers
    /// Where the player is: the dragon looks at them.
    let viewer: ViewerTracker
}

struct DragonBodySystem: System {
    static let query = EntityQuery(where: .has(DragonBodyComponent.self))

    init(scene: RealityKit.Scene) {}

    /// To call once at app launch, before creating the dragon.
    @MainActor
    static func registerAll() {
        DragonNodeComponent.registerComponent()
        DragonBodyComponent.registerComponent()
        OrbitComponent.registerComponent()
        DragonTapTargetComponent.registerComponent()
        DetanglingStateComponent.registerComponent()
        FloatingComponent.registerComponent()
        FloatingSystem.registerSystem()
        IslandHandleComponent.registerComponent()
        TurntableComponent.registerComponent()
        TurntableSystem.registerSystem()
        FocusDimmingComponent.registerComponent()
        FocusDimmingSystem.registerSystem()
        StoryPanelComponent.registerComponent()
        StoryPanelSystem.registerSystem()
        TimeOfDayComponent.registerComponent()
        TimeOfDaySystem.registerSystem()
        registerSystem()
    }

    func update(context: SceneUpdateContext) {
        let deltaTime = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard let body = entity.components[DragonBodyComponent.self] else { continue }
            let viewModel = body.viewModel
            let (viewerInScene, viewerForward) = body.viewer.viewerPose()

            // The grabbed colliders are moved by the ManipulationComponent (the hand): they are the nodes' targets.
            let grabbed = viewModel.userGrabbedNodes
            for index in grabbed {
                viewModel.drag(node: index, to: body.colliders[index].position)
            }

            viewModel.update(deltaTime: deltaTime, viewer: viewerInScene, viewerForward: viewerForward,
                             worldFromLocal: entity.transformMatrix(relativeTo: nil),
                             orbit: entity.components[OrbitComponent.self]?.anchoredOrbit())

            // Story chapter: tap on the island, grab in the mini-game, nothing while flying; the dragon fades
            // in and out.
            if var state = entity.components[DetanglingStateComponent.self] {
                state.apply(phase: viewModel.phase, colliders: body.colliders, config: viewModel.config)
                state.fade(dragonOpacity: viewModel.dragonOpacity, dragon: entity, deltaTime: deltaTime)
                entity.components.set(state)
            }

            // The others follow the dragon (simulation or flight).
            let positions = viewModel.displayPositions
            for (index, collider) in body.colliders.enumerated() where !grabbed.contains(index) {
                collider.position = positions[index]
            }
            body.rig.update(DragonFrame(positions: positions,
                                        mood: viewModel.mood,
                                        action: viewModel.action,
                                        actionProgress: viewModel.actionProgress,
                                        restlessness: viewModel.restlessness,
                                        strain: viewModel.strain,
                                        time: viewModel.time,
                                        lookTarget: viewModel.lookedAtNodeIndex.map { positions[$0] },
                                        viewer: entity.convert(position: viewerInScene, from: nil),
                                        flight: viewModel.flightManeuver.map {
                                            FlightFrame(maneuver: $0, progress: viewModel.flightProgress,
                                                        velocity: viewModel.flightVelocity)
                                        }),
                            deltaTime: deltaTime)
            body.markers.update(points: viewModel.crossingPoints, time: viewModel.time)
        }
    }
}

/// Builds the scene: the play area (no visuals: the dragon lies in the air in front of the player)
/// + the dragon (visual rig + invisible colliders + markers).
enum DragonSceneBuilder {
    static let playAreaName = "PlayArea"
    static let hoverColor = PlatformColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)

    /// `orbitAnchor`: the tree the dragon circles until it is soothed.
    @MainActor
    static func makePlayArea(viewModel: UntangleViewModel, viewer: ViewerTracker, orbitAnchor: Entity) async -> Entity {
        let playArea = Entity()
        playArea.name = playAreaName
        playArea.position = viewModel.placement.position
        playArea.orientation = viewModel.placement.rotation

        let dragon = await makeDragon(viewModel: viewModel, viewer: viewer)
        // Invisible until it is in place around the tree.
        dragon.components.set(OpacityComponent(opacity: 0))
        dragon.components.set(OrbitComponent(anchor: orbitAnchor, path: .aroundTree))
        dragon.components.set(DetanglingStateComponent())
        playArea.addChild(dragon)
        return playArea
    }

    @MainActor
    private static func makeDragon(viewModel: UntangleViewModel, viewer: ViewerTracker) async -> Entity {
        let config = viewModel.config
        let dragon = Entity()
        dragon.name = "Dragon"

        let rig = await DragonRigLoader.load(config: config)
        dragon.addChild(rig.entity)

        // Invisible colliders, one per node: independent from the visuals, they work with any asset.
        // Tappable or grabbable depending on the chapter: `DetanglingStateComponent` configures them.
        let colliders: [Entity] = (0..<config.nodeCount).map { index in
            let collider = Entity()
            collider.name = "DragonNode\(index)"
            collider.position = viewModel.nodePositions[index]
            collider.components.set(DragonNodeComponent(index: index))
            dragon.addChild(collider)
            return collider
        }
        // Hover: the rig puts its visuals under the colliders, so the part being looked at lights up.
        rig.attach(to: colliders)

        let markers = CrossingMarkers(radius: config.radius * 0.8)
        dragon.addChild(markers.entity)

        dragon.components.set(DragonBodyComponent(viewModel: viewModel, rig: rig,
                                                  colliders: colliders, markers: markers, viewer: viewer))
        return dragon
    }

    /// Each node is grabbed with one hand: with two hands two nodes are held together.
    /// `ManipulationComponent` handles one grab per hand; the SwiftUI gesture would handle only one.
    @MainActor
    static func makeGrabbable(_ collider: Entity, config: TangleConfig) {
        // A bit larger than the body, easy to look at and grab, but not much: the spheres of nearby nodes
        // overlap less, so two hands close together pick two different nodes instead of sharing one.
        let shape = ShapeResource.generateSphere(radius: max(config.radius * 1.2, config.segmentLength * 0.75))
        #if os(visionOS)
        ManipulationComponent.configureEntity(
            collider,
            hoverEffect: .highlight(.init(color: hoverColor, strength: 0.8)),
            collisionShapes: [shape]
        )
        var manipulation = ManipulationComponent()
        manipulation.releaseBehavior = .stay
        manipulation.dynamics.translationBehavior = .unconstrained
        manipulation.dynamics.primaryRotationBehavior = .none
        manipulation.dynamics.secondaryRotationBehavior = .none
        manipulation.dynamics.scalingBehavior = .none
        manipulation.dynamics.inertia = .zero
        collider.components.set(manipulation)
        #else
        collider.components.set(CollisionComponent(shapes: [shape]))
        collider.components.set(InputTargetComponent())
        #endif
    }
}

/// Red pulsing spheres on the crossings: they show where the dragon is still tangled.
/// Independent from the rig, so they also work with the real asset's skinned mesh.
@MainActor
final class CrossingMarkers {
    let entity = Entity()
    private var pool: [ModelEntity] = []
    private let mesh: MeshResource
    private let material: UnlitMaterial

    init(radius: Float) {
        mesh = .generateSphere(radius: radius)
        var material = UnlitMaterial(color: PlatformColor(red: 1, green: 0.25, blue: 0.2, alpha: 1))
        material.blending = .transparent(opacity: .init(floatLiteral: 0.55))
        self.material = material
        entity.name = "CrossingMarkers"
    }

    func update(points: [SIMD3<Float>], time: Float) {
        while pool.count < points.count {
            let marker = ModelEntity(mesh: mesh, materials: [material])
            entity.addChild(marker)
            pool.append(marker)
        }
        let pulse = 1 + 0.2 * sin(time * 6)
        for (index, marker) in pool.enumerated() {
            marker.isEnabled = index < points.count
            guard index < points.count else { continue }
            marker.position = points[index]
            marker.scale = SIMD3(repeating: pulse)
        }
    }
}
