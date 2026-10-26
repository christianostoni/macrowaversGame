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

/// The glowing orb of a fruit (`fruitID`), an ingredient of the elixir: it rises out of the open fruit and flies
/// to the orbit at the player's side. Also remembers that journey, which only the RealityKit layer draws.
struct OrbComponent: Component {
    let fruitID: Int
    /// Orbit slot whose colour the orb wears (nil = not found yet, neutral colour).
    var tintedSlot: Int?
    /// Where the flight from the fruit to the orbit started (orchard space) and how long it has lasted.
    var joinStart: SIMD3<Float>?
    var joinElapsed: Float = 0
    /// The player holds it in orbit: the hand moves and turns it, the orbit waits. Let go, it flies back to its
    /// slot like it came from its fruit (`joinStart` starts over).
    var isHeld = false
    /// Size the player gave it with two hands (1 = its own). Let go, it eases back to 1.
    var heldScale: Float = 1

    /// Seconds from the fruit to the orbit.
    static let joinDuration = Elixir.joinDuration
    /// How small and how big two hands can make it.
    static let heldScaleRange: ClosedRange<Float> = 0.5...3
}

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
        case banana(BananaRig)
        case pineapple(PineappleRig)
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
/// focused fruit close or puts it back, applies openings, moves the orbit and the orbs, reads the snap and draws
/// the elixir.
struct OrchardComponent: Component {
    let viewModel: OrchardViewModel
    let viewer: ViewerTracker
    let hands: HandTracker
    /// Where the fruits hang (they turn and bob with the island).
    let island: Entity
    /// Point in front of the player where the focused fruit is shown.
    let stage: Entity
    let fruits: [OrchardFruit]
    /// The orb of each fruit, by fruit id.
    let orbs: [Int: Entity]
    let elixir: ElixirRig
    /// Where the elixir flies: the dragon's head.
    let deliveryTarget: Entity
    /// Interactive things behind the fruit (island rock, dragon colliders): switched off while a fruit is close,
    /// so a pinch that just misses the stem, a worm or the pomegranate never lands on them.
    let background: [Entity]
    let sounds: OrchardSounds
    /// Focus already applied to the entities (`.some(nil)` = all on the tree).
    var appliedFocus: Int??
    var time: Float = 0
    var chop = ChopDetector()
    var snap = SnapDetector()
    /// The small ellipse at the player's side the ingredients go round on.
    var orbit = ElixirOrbit()
    /// The elixir's flight to the dragon, once it has left.
    var flight: ElixirFlight?
    /// Elixir state already drawn: its changes start the flash and the flight.
    var drawnElixirState = ElixirState.gathering
    /// Ingredients already drawn landing in the flask: each new one splashes.
    var drawnLandings = 0
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
        BananaPeelComponent.registerComponent()
        PineappleBodyComponent.registerComponent()
        OrbComponent.registerComponent()
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
                Self.applyOpening(fruit, viewModel: viewModel, time: orchard.time, deltaTime: deltaTime)
            }
            Self.detectChop(&orchard)
            Self.updateOrbit(&orchard, deltaTime: deltaTime)
            Self.detectSnap(&orchard)
            Self.updateOrbs(orchard: orchard, root: entity, deltaTime: deltaTime)
            Self.updateElixir(&orchard, root: entity, deltaTime: deltaTime)
            orchard.sounds.update(orchard)
            entity.components.set(orchard)
        }
    }

    /// Draws the fruit's opening. Sent back to the tree, a fruit closes gently on its way (it never snaps or
    /// vanishes).
    @MainActor
    private static func applyOpening(_ fruit: OrchardFruit, viewModel: OrchardViewModel, time: Float, deltaTime: Float) {
        let isFocused = fruit.fruit.id == viewModel.focusedFruitID
        switch fruit.rig {
        case .apple(let rig):
            rig.ease(towards: isFocused ? viewModel.appleOpening : 0, deltaTime: deltaTime)
            if isFocused {
                rig.apply(worms: viewModel.worms, opening: rig.displayedOpening, time: time)
            }
        case .pomegranate(let rig):
            rig.ease(towards: isFocused ? viewModel.pomegranateOpening : 0,
                     burst: isFocused && viewModel.pomegranateBurst, deltaTime: deltaTime)
        case .banana(let rig):
            rig.ease(towards: isFocused ? viewModel.bananaPeel : rig.displayedPeel.map { _ in 0 }, deltaTime: deltaTime)
        case .pineapple(let rig):
            rig.ease(towards: isFocused && viewModel.pineappleChopped ? 1 : 0, deltaTime: deltaTime)
        }
    }

    /// A hand coming down fast through the pineapple in front of the player chops it (with hand tracking; the
    /// tap works anyway).
    @MainActor
    private static func detectChop(_ orchard: inout OrchardComponent) {
        let viewModel = orchard.viewModel
        guard !viewModel.pineappleChopped,
              let fruit = orchard.fruits.first(where: { $0.fruit.id == viewModel.focusedFruitID }),
              case .pineapple(let rig) = fruit.rig else {
            orchard.chop.reset()
            return
        }
        let target = rig.chopTarget()
        for sample in orchard.hands.samples.values where orchard.chop.process(sample, target: target) {
            viewModel.chopPineapple()
            return
        }
    }

    // MARK: - Zoom-in and back

    @MainActor
    private static func applyFocus(from oldID: Int?, to newID: Int?, orchard: OrchardComponent) {
        for fruit in orchard.fruits where fruit.fruit.id == oldID && oldID != newID {
            // Back on its branch, following the island wherever it turned meanwhile.
            fruit.holder.setParent(orchard.island, preservingWorldTransform: true)
            fruit.holder.components.set(FocusComponent(target: fruit.home, responsiveness: 4))
            fruit.setInteractive(false)
            if case .apple(let rig) = fruit.rig { rig.resetWorms() }
        }
        if let newID, let fruit = orchard.fruits.first(where: { $0.fruit.id == newID }) {
            placeStage(orchard.stage, facing: orchard.viewer.viewerPosition(), from: fruit.holder.position(relativeTo: nil))
            fruit.holder.setParent(orchard.stage, preservingWorldTransform: true)
            fruit.holder.components.set(FocusComponent(target: Transform(scale: SIMD3(repeating: fruit.focusScale)),
                                                       responsiveness: 3.5))
            fruit.setInteractive(true)
        }
        suspendBackground(orchard.background, newID != nil)
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

    /// Off while a fruit is close. Back on only where it belongs: the island's rock always, the dragon's
    /// colliders only while they are tap targets (the dragon still on the island).
    @MainActor
    private static func suspendBackground(_ background: [Entity], _ isSuspended: Bool) {
        for entity in background {
            let isActive = entity.components.has(IslandHandleComponent.self) || entity.components.has(DragonTapTargetComponent.self)
            entity.components[InputTargetComponent.self]?.isEnabled = !isSuspended && isActive
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
}

// MARK: - Building

/// Builds the orchard: fruits hanging on the island's tree, the stage in front of the player, an orb (an
/// ingredient of the elixir) in every fruit and the elixir.
enum OrchardSceneBuilder {
    static let rootName = "Orchard"
    static let stageName = "OrchardStage"

    /// Size on the tree and in front of the player (metres in the scene).
    static let appleSizeOnTree: Float = 0.07
    static let appleSizeFocused: Float = 0.2
    static let pomegranateSizeOnTree: Float = 0.08
    static let pomegranateSizeFocused: Float = 0.14
    static let bananaSizeOnTree: Float = 0.1
    static let bananaSizeFocused: Float = 0.22
    static let pineappleSizeOnTree: Float = 0.09
    static let pineappleSizeFocused: Float = 0.18

    /// What the orchard reads of the player: where their eyes are and what their hands do.
    struct Player {
        let viewer: ViewerTracker
        let hands: HandTracker
    }

    /// - Parameters:
    ///   - island: the fruit hangs from its root at its hang points (it turns and bobs with the island).
    ///   - deliveryTarget: where the elixir flies (the dragon's head).
    ///   - background: interactive entities behind the fruit, switched off while a fruit is close.
    @MainActor
    static func makeOrchard(viewModel: OrchardViewModel, player: Player, island: IslandSceneBuilder.Island,
                            deliveryTarget: Entity, background: [Entity]) async -> Entity {
        let hangPoints = island.fruitHangPoints
        let islandScale = island.root.scale.x
        let root = Entity()
        root.name = rootName
        let stage = Entity()
        stage.name = stageName
        root.addChild(stage)

        let orbTemplate = await makeOrbTemplate()
        var fruits: [OrchardFruit] = []
        var orbs: [Int: Entity] = [:]
        for (index, fruit) in viewModel.fruits.enumerated() {
            let point = hangPoints.isEmpty ? .zero : hangPoints[index % hangPoints.count]
            guard let orchardFruit = await makeFruit(fruit, at: point, islandScale: islandScale, viewModel: viewModel) else {
                continue
            }
            island.root.addChild(orchardFruit.holder)
            fruits.append(orchardFruit)
            let orb = orbTemplate.clone(recursive: true)
            orb.name = "Orb\(fruit.id)"
            orb.components.set(OrbComponent(fruitID: fruit.id))
            orb.isEnabled = false
            orchardFruit.orbAnchor.addChild(orb)
            orbs[fruit.id] = orb
        }

        let elixir = await ElixirRig.make()
        root.addChild(elixir.elixir)
        root.addChild(elixir.hintAnchor)

        let sounds = OrchardSounds()
        Task { await sounds.load() }
        root.components.set(OrchardComponent(viewModel: viewModel, viewer: player.viewer, hands: player.hands,
                                             island: island.root, stage: stage, fruits: fruits, orbs: orbs,
                                             elixir: elixir, deliveryTarget: deliveryTarget, background: background,
                                             sounds: sounds))
        return root
    }

    /// A fruit's drawing and its sizes, before it is hung on the tree.
    private struct RigBuild {
        let rig: OrchardFruit.Rig
        let root: Entity
        /// Height of the drawing in its own units.
        let size: Float
        let tapShape: ShapeResource
        let treeSize: Float
        let focusedSize: Float
    }

    @MainActor
    private static func makeRig(_ kind: FruitKind, viewModel: OrchardViewModel) async -> RigBuild? {
        switch kind {
        case .apple:
            let shape = viewModel.appleShape
            guard let apple = AppleRig(shape: shape, wormCount: viewModel.wormCount) else { return nil }
            return RigBuild(rig: .apple(apple), root: apple.root, size: shape.height,
                            tapShape: .generateSphere(radius: shape.height * 0.9),
                            treeSize: appleSizeOnTree, focusedSize: appleSizeFocused)
        case .pomegranate:
            guard let pomegranate = await PomegranateRig() else { return nil }
            return RigBuild(rig: .pomegranate(pomegranate), root: pomegranate.root, size: pomegranate.radius * 2,
                            tapShape: .generateSphere(radius: pomegranate.radius * 1.8),
                            treeSize: pomegranateSizeOnTree, focusedSize: pomegranateSizeFocused)
        case .banana:
            guard let banana = await BananaRig() else { return nil }
            return RigBuild(rig: .banana(banana), root: banana.root, size: banana.size,
                            tapShape: .generateSphere(radius: banana.size * 0.6),
                            treeSize: bananaSizeOnTree, focusedSize: bananaSizeFocused)
        case .pineapple:
            guard let pineapple = await PineappleRig() else { return nil }
            return RigBuild(rig: .pineapple(pineapple), root: pineapple.root, size: pineapple.size,
                            tapShape: .generateSphere(radius: pineapple.size * 0.8),
                            treeSize: pineappleSizeOnTree, focusedSize: pineappleSizeFocused)
        }
    }

    @MainActor
    private static func makeFruit(_ fruit: Fruit, at point: SIMD3<Float>, islandScale: Float,
                                  viewModel: OrchardViewModel) async -> OrchardFruit? {
        guard let build = await makeRig(fruit.kind, viewModel: viewModel) else { return nil }
        let holder = Entity()
        holder.name = "Fruit\(fruit.id)"
        // Gentle sway on the branch (and in front of the player).
        let sway = Entity()
        sway.components.set(FloatingComponent(base: .zero, amplitude: 0.006, period: 3.5 + Float(fruit.id) * 0.4,
                                              phase: Float(fruit.id)))
        holder.addChild(sway)
        sway.addChild(build.root)

        let home = Transform(scale: SIMD3(repeating: build.treeSize / build.size / islandScale),
                             rotation: simd_quatf(angle: Float(fruit.id) * 1.3, axis: SIMD3(0, 1, 0)),
                             translation: point)
        holder.transform = home
        holder.components.set(FruitComponent(id: fruit.id, kind: fruit.kind))
        // Larger than the fruit: it is small and far away on the tree.
        holder.components.set(FruitTapTargetComponent(shape: build.tapShape))
        holder.components.set(CollisionComponent(shapes: [build.tapShape]))
        holder.components.set(InputTargetComponent())
        holder.components.set(HoverEffectComponent())
        return OrchardFruit(fruit: fruit, holder: holder, rig: build.rig, home: home,
                            focusScale: build.focusedSize / build.size)
    }
}

// MARK: - Per-fruit drawing

extension OrchardFruit {
    /// Where the fruit's orb sits until it rises.
    @MainActor
    var orbAnchor: Entity {
        switch rig {
        case .apple(let rig): rig.core
        case .pomegranate(let rig): rig.orbAnchor
        case .banana(let rig): rig.orbAnchor
        case .pineapple(let rig): rig.orbAnchor
        }
    }

    /// How high above its anchor the freed orb floats, in the fruit's own units.
    @MainActor
    func orbHeight(viewModel: OrchardViewModel) -> Float {
        switch rig {
        case .apple(let rig): rig.shape.height / 2 + viewModel.appleOpening * rig.shape.maxLift + 0.07
        case .pomegranate(let rig): rig.radius * 0.9 + 0.07
        case .banana(let rig): rig.heightAboveAnchor + 0.05
        case .pineapple(let rig): rig.size / 2 + 0.07
        }
    }

    /// The sealed orb shows only in the apple: between its slices, guarded by the worms.
    var showsSealedOrb: Bool {
        if case .apple = rig { return true }
        return false
    }

    /// The fruit's own targets (stem, worms, halves, peel) answer only while it is close to the player.
    @MainActor
    func setInteractive(_ isInteractive: Bool) {
        switch rig {
        case .apple(let rig): rig.setInteractive(isInteractive)
        case .pomegranate(let rig): rig.setInteractive(isInteractive)
        case .banana(let rig): rig.setInteractive(isInteractive)
        case .pineapple(let rig): rig.setInteractive(isInteractive)
        }
    }
}
