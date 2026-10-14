import RealityKit
import simd
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Indice del nodo (vertebra) del corpo: serve a sapere quale punto è stato afferrato.
struct DragonNodeComponent: Component {
    let index: Int
}

/// Collega il drago al ViewModel. Ogni frame il `DragonBodySystem` legge dove le mani hanno portato
/// i collider afferrati, fa avanzare il gioco, riallinea gli altri collider e aggiorna il rig (grafica).
struct DragonBodyComponent: Component {
    let viewModel: UntangleViewModel
    let rig: DragonRig
    let colliders: [Entity]
    let markers: CrossingMarkers
    /// Dove si trova l'utente: il drago lo guarda.
    let viewer: ViewerTracker
}

struct DragonBodySystem: System {
    static let query = EntityQuery(where: .has(DragonBodyComponent.self))

    init(scene: RealityKit.Scene) {}

    /// Da chiamare una volta all'avvio dell'app, prima di creare il drago.
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
        registerSystem()
    }

    func update(context: SceneUpdateContext) {
        let deltaTime = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard let body = entity.components[DragonBodyComponent.self] else { continue }
            let viewModel = body.viewModel
            let viewerInScene = body.viewer.viewerPosition()

            // I collider afferrati li muove il ManipulationComponent (la mano): sono il bersaglio dei nodi.
            let grabbed = viewModel.userGrabbedNodes
            for index in grabbed {
                viewModel.drag(node: index, to: body.colliders[index].position)
            }

            viewModel.update(deltaTime: deltaTime, viewer: viewerInScene,
                             worldFromLocal: entity.transformMatrix(relativeTo: nil),
                             orbit: entity.components[OrbitComponent.self]?.anchoredOrbit())

            // Capitolo della storia: tocco sull'isola, presa nel minigioco, niente in volo; il drago appare
            // e sparisce con dissolvenza.
            if var state = entity.components[DetanglingStateComponent.self] {
                state.apply(phase: viewModel.phase, colliders: body.colliders, config: viewModel.config)
                state.fade(dragonOpacity: viewModel.dragonOpacity, dragon: entity, deltaTime: deltaTime)
                entity.components.set(state)
            }

            // Gli altri seguono il drago (simulazione o volo).
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

/// Costruisce la scena: area di gioco (senza grafica: il drago giace nell'aria davanti all'utente)
/// + drago (rig grafico + collider invisibili + indicatori).
enum DragonSceneBuilder {
    static let playAreaName = "PlayArea"
    static let hoverColor = PlatformColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)

    /// `orbitAnchor`: l'albero attorno a cui il drago gira finché l'utente non lo tocca.
    @MainActor
    static func makePlayArea(viewModel: UntangleViewModel, viewer: ViewerTracker, orbitAnchor: Entity) async -> Entity {
        let playArea = Entity()
        playArea.name = playAreaName
        playArea.position = viewModel.placement.position
        playArea.orientation = viewModel.placement.rotation

        let dragon = await makeDragon(viewModel: viewModel, viewer: viewer)
        // Invisibile finché non è al suo posto attorno all'albero.
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

        // Collider invisibili, uno per nodo: indipendenti dalla grafica, funzionano con qualsiasi asset.
        // Toccabili o afferrabili secondo la fase: li configura `DetanglingStateComponent`.
        let colliders: [Entity] = (0..<config.nodeCount).map { index in
            let collider = Entity()
            collider.name = "DragonNode\(index)"
            collider.position = viewModel.nodePositions[index]
            collider.components.set(DragonNodeComponent(index: index))
            dragon.addChild(collider)
            return collider
        }
        // Hover: il rig mette la sua grafica sotto i collider, così si illumina la parte guardata.
        rig.attach(to: colliders)

        let markers = CrossingMarkers(radius: config.radius * 0.8)
        dragon.addChild(markers.entity)

        dragon.components.set(DragonBodyComponent(viewModel: viewModel, rig: rig,
                                                  colliders: colliders, markers: markers, viewer: viewer))
        return dragon
    }

    /// Ogni nodo si afferra con una mano: con due mani si tengono due nodi insieme.
    /// `ManipulationComponent` gestisce una presa per mano; il gesto SwiftUI ne gestirebbe una sola.
    @MainActor
    static func makeGrabbable(_ collider: Entity, radius: Float) {
        // Un po' più grande del corpo: più facile da guardare e afferrare.
        let shape = ShapeResource.generateSphere(radius: radius * 1.5)
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

/// Sfere rosse pulsanti sugli incroci: mostrano dove il drago è ancora aggrovigliato.
/// Indipendenti dal rig, quindi funzionano anche con la mesh skinnata dell'asset vero.
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
