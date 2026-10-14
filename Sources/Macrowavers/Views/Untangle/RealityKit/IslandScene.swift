import Foundation
import RealityKit
import simd

/// Fluttuazione lenta su e giù (isola, rocce sospese): dà profondità e vita senza distrarre.
/// Rocce e isola hanno periodi diversi, quindi si muovono una rispetto all'altra (parallasse).
struct FloatingComponent: Component {
    /// Posizione di riposo, nello spazio del genitore.
    var base: SIMD3<Float>
    /// Direzione "su" nello spazio del genitore (l'asset può avere una rotazione sulla radice).
    var axis: SIMD3<Float> = SIMD3(0, 1, 0)
    /// Ampiezza nello spazio del genitore.
    var amplitude: Float
    var period: Float
    var phase: Float = 0
    var time: Float = 0
}

struct FloatingSystem: System {
    static let query = EntityQuery(where: .has(FloatingComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let deltaTime = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var floating = entity.components[FloatingComponent.self] else { continue }
            floating.time += deltaTime
            let offset = floating.amplitude * sin(2 * .pi * floating.time / floating.period + floating.phase)
            entity.position = floating.base + floating.axis * offset
            entity.components.set(floating)
        }
    }
}

/// Costruisce l'isola volante con l'albero al centro: il drago prigioniero gli gira attorno.
enum IslandSceneBuilder {
    static let islandName = "FloatingIsland"
    static let treeAnchorName = "TreeAnchor"

    /// `treeAnchor` è la base del tronco (origine dell'asset): il centro dell'orbita del drago.
    /// Se l'asset manca, l'ancora c'è comunque e il drago gira attorno al punto vuoto.
    @MainActor
    static func makeIsland(placement: IslandPlacement) async -> (root: Entity, treeAnchor: Entity) {
        let root = Entity()
        root.name = islandName
        root.position = placement.position
        root.orientation = placement.rotation
        root.scale = SIMD3(repeating: placement.scale)
        root.components.set(FloatingComponent(base: placement.position, amplitude: 0.02, period: 7))

        do {
            let model = try await Entity(named: islandName, in: .main)
            root.addChild(model)
            // Le rocce sospese fluttuano per conto loro, più veloci dell'isola.
            if let rocks = model.findEntity(named: "FloatingRocks"), let parent = rocks.parent {
                let up = parent.convert(direction: SIMD3(0, 1, 0), from: root)
                rocks.components.set(FloatingComponent(base: rocks.position, axis: simd_normalize(up),
                                                       amplitude: 0.05 * simd_length(up), period: 4.5, phase: 1.3))
            }
        } catch {
            print("⚠️ \(islandName).usdz not found: the dragon circles an empty spot (\(error))")
        }

        let treeAnchor = Entity()
        treeAnchor.name = treeAnchorName
        root.addChild(treeAnchor)
        return (root, treeAnchor)
    }
}
