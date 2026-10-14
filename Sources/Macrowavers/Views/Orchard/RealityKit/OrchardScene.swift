import Foundation
import RealityKit
import simd
import UIKit

// MARK: - Components

extension InputTargetComponent {
    /// Input target that starts switched off (turned on when the entity becomes interactive).
    static var disabled: InputTargetComponent {
        var target = InputTargetComponent()
        target.isEnabled = false
        return target
    }
}

/// A fruit hanging on the tree (on its holder entity).
struct FruitComponent: Component {
    let id: Int
    let kind: FruitKind
}

/// Tappable fruit on the tree: the tap brings it close. Holds its collision shape, removed while the fruit is
/// close (it would hide the stem, the worms and the seeds from the player's gaze).
struct FruitTapTargetComponent: Component {
    let shape: ShapeResource
}

/// The apple's stem: pull it up to open the apple.
struct AppleStemComponent: Component {}

/// A worm in the apple (index in `WormSwarm.worms`).
struct WormComponent: Component {
    let index: Int
}

/// The pomegranate's body: pull it apart with two hands.
struct PomegranateBodyComponent: Component {}

/// A pomegranate seed.
struct SeedComponent: Component {}

/// The artifact that soothes the dragon.
struct ArtifactComponent: Component {}

/// Smoothly moves an entity to `target` (in its parent's space), then removes itself.
struct FocusComponent: Component {
    var target: Transform
    /// How fast it gets there (1/s).
    var responsiveness: Float = 5
}

struct FocusSystem: System {
    static let query = EntityQuery(where: .has(FocusComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let deltaTime = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard let focus = entity.components[FocusComponent.self] else { continue }
            let amount = 1 - exp(-deltaTime * focus.responsiveness)
            var transform = entity.transform
            transform.translation = simd_mix(transform.translation, focus.target.translation, SIMD3(repeating: amount))
            transform.scale = simd_mix(transform.scale, focus.target.scale, SIMD3(repeating: amount))
            transform.rotation = simd_slerp(transform.rotation, focus.target.rotation, amount)
            let isThere = simd_distance(transform.translation, focus.target.translation) < 0.0005
                && simd_distance(transform.scale, focus.target.scale) < 0.001
            if isThere {
                entity.transform = focus.target
                entity.components.remove(FocusComponent.self)
            } else {
                entity.transform = transform
            }
        }
    }
}

/// One fruit of the orchard: holder on the tree, drawing, rest position.
struct OrchardFruit {
    enum Rig {
        case apple(AppleRig)
        case pomegranate(PomegranateRig)
    }

    let fruit: Fruit
    let holder: Entity
    let rig: Rig
    /// Rest transform on the tree (island space).
    let home: Transform
    /// Scale in front of the player (stage space).
    let focusScale: Float
}

/// Connects the orchard to its view model. Every frame the `OrchardSystem` advances the worms, brings the
/// focused fruit close or puts it back, applies openings and moves the artifact.
struct OrchardComponent: Component {
    let viewModel: OrchardViewModel
    let viewer: ViewerTracker
    /// Where the fruits hang (they turn and bob with the island).
    let island: Entity
    /// Point in front of the player where the focused fruit is shown.
    let stage: Entity
    let fruits: [OrchardFruit]
    let artifact: Entity
    /// Where the artifact flies when used: the dragon's head.
    let deliveryTarget: Entity
    /// Focus already applied to the entities (`.some(nil)` = all on the tree).
    var appliedFocus: Int??
    var time: Float = 0

    /// Speed of the artifact flying to the dragon (m/s).
    static let artifactSpeed: Float = 1.1
}

struct OrchardSystem: System {
    static let query = EntityQuery(where: .has(OrchardComponent.self))

    init(scene: RealityKit.Scene) {}

    /// To call once at app launch, before building the orchard.
    @MainActor
    static func registerAll() {
        FruitComponent.registerComponent()
        FruitTapTargetComponent.registerComponent()
        AppleStemComponent.registerComponent()
        WormComponent.registerComponent()
        PomegranateBodyComponent.registerComponent()
        SeedComponent.registerComponent()
        ArtifactComponent.registerComponent()
        FocusComponent.registerComponent()
        OrchardComponent.registerComponent()
        FocusSystem.registerSystem()
        registerSystem()
    }

    func update(context: SceneUpdateContext) {
        let deltaTime = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var orchard = entity.components[OrchardComponent.self] else { continue }
            let viewModel = orchard.viewModel
            orchard.time += deltaTime
            viewModel.update(deltaTime: deltaTime)

            if orchard.appliedFocus != .some(viewModel.focusedFruitID) {
                Self.applyFocus(from: orchard.appliedFocus ?? nil, to: viewModel.focusedFruitID, orchard: orchard)
                orchard.appliedFocus = .some(viewModel.focusedFruitID)
            }
            for fruit in orchard.fruits {
                let isFocused = fruit.fruit.id == viewModel.focusedFruitID
                switch fruit.rig {
                case .apple(let rig):
                    rig.apply(opening: isFocused ? viewModel.appleOpening : 0)
                    if isFocused { rig.apply(worms: viewModel.worms, opening: viewModel.appleOpening, time: orchard.time) }
                case .pomegranate(let rig):
                    rig.apply(opening: isFocused ? viewModel.pomegranateOpening : 0,
                              burst: isFocused && viewModel.pomegranateBurst)
                }
            }
            Self.updateArtifact(orchard: orchard, root: entity, deltaTime: deltaTime)
            entity.components.set(orchard)
        }
    }

    // MARK: - Zoom-in and back

    @MainActor
    private static func applyFocus(from oldID: Int?, to newID: Int?, orchard: OrchardComponent) {
        for fruit in orchard.fruits where fruit.fruit.id == oldID && oldID != newID {
            // Back on its branch, following the island wherever it turned meanwhile.
            fruit.holder.setParent(orchard.island, preservingWorldTransform: true)
            fruit.holder.components.set(FocusComponent(target: fruit.home, responsiveness: 4))
            setInteractive(fruit, false)
            if case .apple(let rig) = fruit.rig { rig.resetWorms() }
        }
        if let newID, let fruit = orchard.fruits.first(where: { $0.fruit.id == newID }) {
            placeStage(orchard.stage, facing: orchard.viewer.viewerPosition(), from: fruit.holder.position(relativeTo: nil))
            fruit.holder.setParent(orchard.stage, preservingWorldTransform: true)
            fruit.holder.components.set(FocusComponent(target: Transform(scale: SIMD3(repeating: fruit.focusScale)),
                                                       responsiveness: 3.5))
            setInteractive(fruit, true)
        }
        // Fruits on the tree can be picked only while none is close.
        for fruit in orchard.fruits where fruit.fruit.id != newID {
            setTappable(fruit.holder, newID == nil)
        }
        if let newID, let fruit = orchard.fruits.first(where: { $0.fruit.id == newID }) {
            setTappable(fruit.holder, false)
        }
    }

    /// The stage stands between the player and the fruit, ~50 cm from the eyes and a little below them,
    /// turned so that its +Z faces the player.
    @MainActor
    private static func placeStage(_ stage: Entity, facing viewer: SIMD3<Float>, from fruit: SIMD3<Float>) {
        var direction = fruit - viewer
        direction.y = 0
        direction = simd_length(direction) > 1e-4 ? simd_normalize(direction) : SIMD3(0, 0, -1)
        stage.position = viewer + direction * 0.5 - SIMD3(0, 0.12, 0)
        stage.orientation = simd_quatf(angle: atan2(-direction.x, -direction.z), axis: SIMD3(0, 1, 0))
    }

    @MainActor
    private static func setInteractive(_ fruit: OrchardFruit, _ isInteractive: Bool) {
        switch fruit.rig {
        case .apple(let rig): rig.setInteractive(isInteractive)
        case .pomegranate(let rig): rig.setInteractive(isInteractive)
        }
    }

    @MainActor
    private static func setTappable(_ holder: Entity, _ isTappable: Bool) {
        guard let target = holder.components[FruitTapTargetComponent.self] else { return }
        if isTappable {
            holder.components.set(CollisionComponent(shapes: [target.shape]))
            holder.components.set(InputTargetComponent())
        } else {
            holder.components.remove(CollisionComponent.self)
            holder.components.remove(InputTargetComponent.self)
        }
    }

    // MARK: - Artifact

    @MainActor
    private static func updateArtifact(orchard: OrchardComponent, root: Entity, deltaTime: Float) {
        let viewModel = orchard.viewModel
        let artifact = orchard.artifact
        let focusedApple = orchard.fruits.first { $0.fruit.id == viewModel.focusedFruitID }.flatMap { fruit -> AppleRig? in
            if case .apple(let rig) = fruit.rig { return rig }
            return nil
        }
        let pulse = 1 + 0.08 * sin(orchard.time * 4)

        switch viewModel.artifact {
        case .hidden, .used:
            artifact.isEnabled = false
        case .guarded:
            // Locked in the core: visible between the slices, not yet tappable.
            guard let focusedApple else {
                artifact.isEnabled = false
                return
            }
            attach(artifact, to: focusedApple.core)
            artifact.isEnabled = true
            artifact.position = .zero
            artifact.setScale(SIMD3(repeating: 0.7), relativeTo: nil)
            artifact.components[InputTargetComponent.self]?.isEnabled = false
        case .revealed:
            guard let focusedApple, viewModel.focusedFruitID == viewModel.artifactFruitID else {
                artifact.isEnabled = false
                return
            }
            attach(artifact, to: focusedApple.core)
            artifact.isEnabled = true
            // Rises out of the opened apple and floats above it.
            let rise = min(viewModel.artifactRevealTime / 1.2, 1)
            let eased = rise * rise * (3 - 2 * rise)
            let above = focusedApple.shape.height / 2 + viewModel.appleOpening * focusedApple.shape.maxLift + 0.07
            artifact.position = SIMD3(0, above * eased + 0.01 * sin(orchard.time * 2), 0)
            artifact.setScale(SIMD3(repeating: pulse), relativeTo: nil)
            artifact.components[InputTargetComponent.self]?.isEnabled = rise >= 1
        case .flying:
            if artifact.parent !== root { artifact.setParent(root, preservingWorldTransform: true) }
            artifact.isEnabled = true
            artifact.components[InputTargetComponent.self]?.isEnabled = false
            let target = orchard.deliveryTarget.position(relativeTo: root)
            let offset = target - artifact.position
            let distance = simd_length(offset)
            if distance < 0.05 {
                artifact.isEnabled = false
                viewModel.artifactDelivered()
            } else {
                artifact.position += offset / distance * min(distance, OrchardComponent.artifactSpeed * deltaTime)
                artifact.setScale(SIMD3(repeating: pulse), relativeTo: nil)
            }
        }
    }

    @MainActor
    private static func attach(_ artifact: Entity, to parent: Entity) {
        guard artifact.parent !== parent else { return }
        artifact.setParent(parent, preservingWorldTransform: false)
    }
}

// MARK: - Building

/// Builds the orchard: fruits hanging on the island's tree, the stage in front of the player, the artifact.
enum OrchardSceneBuilder {
    static let rootName = "Orchard"
    static let stageName = "OrchardStage"

    /// Size on the tree and in front of the player (metres in the scene).
    static let appleSizeOnTree: Float = 0.07
    static let appleSizeFocused: Float = 0.2
    static let pomegranateSizeOnTree: Float = 0.08
    static let pomegranateSizeFocused: Float = 0.14

    /// - Parameters:
    ///   - island: the fruit hangs from its root at its hang points (it turns and bobs with the island).
    ///   - deliveryTarget: where the artifact flies (the dragon's head).
    @MainActor
    static func makeOrchard(viewModel: OrchardViewModel, viewer: ViewerTracker, island: IslandSceneBuilder.Island,
                            deliveryTarget: Entity) async -> Entity {
        let hangPoints = island.fruitHangPoints
        let islandScale = island.root.scale.x
        let root = Entity()
        root.name = rootName
        let stage = Entity()
        stage.name = stageName
        root.addChild(stage)

        var fruits: [OrchardFruit] = []
        for (index, fruit) in viewModel.fruits.enumerated() {
            let point = hangPoints.isEmpty ? .zero : hangPoints[index % hangPoints.count]
            if let orchardFruit = makeFruit(fruit, at: point, islandScale: islandScale, shape: viewModel.appleShape,
                                            wormCount: viewModel.wormCount) {
                island.root.addChild(orchardFruit.holder)
                fruits.append(orchardFruit)
            }
        }

        let artifact = await makeArtifact()
        artifact.isEnabled = false
        root.addChild(artifact)

        root.components.set(OrchardComponent(viewModel: viewModel, viewer: viewer, island: island.root, stage: stage,
                                             fruits: fruits, artifact: artifact, deliveryTarget: deliveryTarget))
        return root
    }

    @MainActor
    private static func makeFruit(_ fruit: Fruit, at point: SIMD3<Float>, islandScale: Float,
                                  shape: AppleShape, wormCount: Int) -> OrchardFruit? {
        let holder = Entity()
        holder.name = "Fruit\(fruit.id)"
        // Gentle sway on the branch (and in front of the player).
        let sway = Entity()
        sway.components.set(FloatingComponent(base: .zero, amplitude: 0.006, period: 3.5 + Float(fruit.id) * 0.4,
                                              phase: Float(fruit.id)))
        holder.addChild(sway)

        let rig: OrchardFruit.Rig
        let size: Float
        let tapShape: ShapeResource
        let treeSize: Float
        let focusedSize: Float
        switch fruit.kind {
        case .apple:
            guard let apple = AppleRig(shape: shape, wormCount: wormCount) else { return nil }
            sway.addChild(apple.root)
            rig = .apple(apple)
            size = shape.height
            tapShape = .generateSphere(radius: shape.height * 0.9)
            treeSize = appleSizeOnTree
            focusedSize = appleSizeFocused
        case .pomegranate:
            guard let pomegranate = PomegranateRig() else { return nil }
            sway.addChild(pomegranate.root)
            rig = .pomegranate(pomegranate)
            size = pomegranate.radius * 2
            tapShape = .generateSphere(radius: pomegranate.radius * 1.8)
            treeSize = pomegranateSizeOnTree
            focusedSize = pomegranateSizeFocused
        }

        let home = Transform(scale: SIMD3(repeating: treeSize / size / islandScale),
                             rotation: simd_quatf(angle: Float(fruit.id) * 1.3, axis: SIMD3(0, 1, 0)),
                             translation: point)
        holder.transform = home
        holder.components.set(FruitComponent(id: fruit.id, kind: fruit.kind))
        // Larger than the fruit: it is small and far away on the tree.
        holder.components.set(FruitTapTargetComponent(shape: tapShape))
        holder.components.set(CollisionComponent(shapes: [tapShape]))
        holder.components.set(InputTargetComponent())
        holder.components.set(HoverEffectComponent())
        return OrchardFruit(fruit: fruit, holder: holder, rig: rig, home: home, focusScale: focusedSize / size)
    }

    /// The artifact: `Artifact.usdz` from the bundle when the design team delivers it, otherwise a glowing
    /// golden orb (placeholder). Origin at its centre, about 5 cm wide.
    @MainActor
    private static func makeArtifact() async -> Entity {
        let artifact = Entity()
        artifact.name = "Artifact"
        if let asset = try? await Entity(named: "Artifact", in: .main) {
            artifact.addChild(asset)
        } else {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: UIColor(red: 1, green: 0.8, blue: 0.35, alpha: 1))
            material.emissiveColor = .init(color: UIColor(red: 1, green: 0.75, blue: 0.3, alpha: 1))
            material.emissiveIntensity = 2.5
            material.metallic = 0.6
            material.roughness = 0.2
            artifact.addChild(ModelEntity(mesh: .generateSphere(radius: 0.025), materials: [material]))
            var halo = UnlitMaterial(color: UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1))
            halo.blending = .transparent(opacity: .init(floatLiteral: 0.25))
            artifact.addChild(ModelEntity(mesh: .generateSphere(radius: 0.038), materials: [halo]))
        }
        artifact.components.set(ArtifactComponent())
        artifact.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.05)]))
        artifact.components.set(InputTargetComponent.disabled)
        artifact.components.set(HoverEffectComponent())
        return artifact
    }
}
