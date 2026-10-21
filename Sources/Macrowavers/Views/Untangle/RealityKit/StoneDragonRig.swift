import Foundation
import RealityKit
import simd

/// Rig for the design team's stone dragon (`StoneDragon.usdz`, made by `Assets/Blender/stone-dragon`): a head and a
/// chain of separate stones. Used automatically when the asset is in the bundle.
///
/// - `Head`: origin at the face's centre, snout towards +Z, +Y up. `JawHinge` turns around its +X to open the mouth
///   (the lower jaw hangs from it); `mouth` and `nostrils` mark where fire and smoke come out.
/// - `Stone_00` (behind the head) … `Stone_NN` (the tail): each with its origin at its centre, +Z along the body
///   towards the tail, +Y up. Their rest distances from the head place them along the simulated body
///   (`StoneDragonLayout`).
///
/// Every frame each stone sits on the smoothed body at its distance from the head, turned along it, breathing and
/// floating a few millimetres on its own. Each stone hangs from the collider of the node that holds it, so it lights
/// up when looked at and the player grabs it: only those nodes are grabbable (`grabTargets`), with a sphere the size
/// of their stone.
@MainActor
final class StoneDragonRig: DragonRig {
    enum Asset {
        static let name = "StoneDragon"
        static let head = "Head"
        static let jawHinge = "JawHinge"
        static let stonePrefix = "Stone_"
        /// The stones' size compared with the design's proportions along the body (1 = as modelled, nearly
        /// touching). A little smaller leaves a thin gap between them (1–2 cm) and keeps them closer to the
        /// simulated body's thickness (8 cm; the widest stone is ~13 cm), so crossings overlap less.
        static let stoneScale: Float = 0.9
        /// How far the jaw turns when the mouth is wide open (radians).
        static let jawAngle: Float = 0.6
        /// Stretch of neck (m) that leaves the back of the head in its direction before reaching the body.
        static let neckBlendLength: Float = 0.18
        /// How far each stone floats on its own (m), and how fast.
        static let floatHeight: Float = 0.003
        static let floatSpeed: Float = 1.6
        /// The grab sphere around a stone, as a share of half the distance to the next stone: as large as it can be
        /// without overlapping its neighbour's, so two hands always take two different stones.
        static let grabReach: Float = 0.95
    }

    let entity = Entity()
    /// Node → radius of its grab sphere: one per stone.
    let grabTargets: [Int: Float]?

    private var animator: DragonLifeAnimator
    private let layout: StoneDragonLayout
    /// One per stone: placed every frame; the stone's model is its child.
    private let holders: [Entity]
    private let headAnchor = Entity()
    private let jawHinge: Entity?
    private let jawRest: simd_quatf
    private let effects = DragonEffects()
    /// Colliders the holders are attached to (for hover and grabs); empty = holders are children of `entity`.
    private var colliders: [Entity] = []
    /// Each stone's last "up": kept when the body points straight up or down, where world up says nothing.
    private var ups: [SIMD3<Float>]

    static func load(config: TangleConfig) async -> StoneDragonRig? {
        guard let root = try? await Entity(named: Asset.name, in: .main) else { return nil }
        guard let head = root.findEntity(named: Asset.head) else {
            print("⚠️ \(Asset.name): no '\(Asset.head)', using another dragon.")
            return nil
        }
        let stones = (0..<100).lazy
            .map { root.findEntity(named: String(format: "\(Asset.stonePrefix)%02d", $0)) }
            .prefix { $0 != nil }
            .compactMap { $0 }
        guard stones.count >= 2 else {
            print("⚠️ \(Asset.name): needs at least 2 '\(Asset.stonePrefix)NN' stones, found \(stones.count).")
            return nil
        }
        return StoneDragonRig(config: config, root: root, head: head, stones: Array(stones))
    }

    private init(config: TangleConfig, root: Entity, head: Entity, stones: [Entity]) {
        let layout = StoneDragonLayout(head: head.position(relativeTo: root),
                                       restCentres: stones.map { $0.position(relativeTo: root) }, config: config)
        // One scale for the stones and the head: the design's proportions along the simulated body.
        let scale = Asset.stoneScale * layout.scale

        var targets: [Int: Float] = [:]
        var holders: [Entity] = []
        for (index, stone) in stones.enumerated() {
            stone.removeFromParent()
            // The stone's own frame is the one the code turns: its rest place is now the layout's.
            stone.transform = Transform(scale: SIMD3(repeating: scale))
            Self.castShadows(stone)
            let holder = Entity()
            holder.name = "StoneHolder\(index)"
            holder.addChild(stone)
            holders.append(holder)
            targets[layout.nodes[index]] = Asset.grabReach * layout.halfGap(around: index)
        }

        head.removeFromParent()
        head.transform = Transform(scale: SIMD3(repeating: scale))
        Self.castShadows(head)
        let jawHinge = head.findEntity(named: Asset.jawHinge)

        animator = DragonLifeAnimator(config: config)
        self.layout = layout
        self.holders = holders
        grabTargets = targets
        ups = Array(repeating: SIMD3(0, 1, 0), count: stones.count)
        self.jawHinge = jawHinge
        jawRest = jawHinge?.orientation ?? simd_quatf(angle: 0, axis: SIMD3(1, 0, 0))

        entity.name = "StoneDragon"
        holders.forEach { entity.addChild($0) }
        headAnchor.name = "StoneDragonHead"
        headAnchor.addChild(head)
        entity.addChild(headAnchor)
        let nostrils = head.findEntity(named: "nostrils") ?? Self.marker(in: head, at: SIMD3(0, 0.01, 0.15))
        let mouth = head.findEntity(named: "mouth") ?? Self.marker(in: head, at: SIMD3(0, -0.03, 0.14))
        effects.attach(nostrils: nostrils, mouth: mouth, voice: headAnchor)
    }

    /// Each stone hangs from the collider of its node: looking at it lights up exactly that stone.
    func attach(to colliders: [Entity]) {
        guard let last = layout.nodes.last, last < colliders.count else { return }
        self.colliders = colliders
        for (index, holder) in holders.enumerated() {
            colliders[layout.nodes[index]].addChild(holder)
        }
    }

    func update(_ frame: DragonFrame, deltaTime: Float) {
        animator.update(frame, deltaTime: deltaTime)
        let pose = animator.pose
        let visual = DragonCurve.neckFollowingHead(animator.visualPositions(frame), headOrientation: pose.headOrientation,
                                                   blendLength: Asset.neckBlendLength)
        headAnchor.position = visual[0]
        headAnchor.orientation = pose.headOrientation
        jawHinge?.orientation = jawRest * simd_quatf(angle: pose.jawOpen * Asset.jawAngle, axis: SIMD3(1, 0, 0))
        effects.update(pose: pose, frame: frame)

        let curve = DragonCurve.smoothed(visual)
        for (index, holder) in holders.enumerated() {
            let arc = layout.arcLengths[index]
            let ahead = DragonCurve.point(on: curve, atArcLength: arc + 0.02)
            let behind = DragonCurve.point(on: curve, atArcLength: max(arc - 0.02, 0))
            guard simd_length(ahead - behind) > 1e-6 else { continue }
            // +Z along the body towards the tail, +Y as close to world up as the body allows.
            let along = simd_normalize(ahead - behind)
            var up = SIMD3<Float>(0, 1, 0) - along * along.y
            up = simd_length(up) > 0.2 ? simd_normalize(up) : simd_normalize(ups[index] - along * simd_dot(ups[index], along))
            ups[index] = up
            let right = simd_cross(up, along)
            let orientation = simd_quatf(float3x3(columns: (right, up, along)))

            let node = layout.nodes[index]
            let bob = Asset.floatHeight * sin(frame.time * Asset.floatSpeed + Float(index) * 0.7)
            let position = DragonCurve.point(on: curve, atArcLength: arc) + up * bob
            // When attached to the collider, the position is relative to it (which may already be in the hand).
            holder.position = colliders.isEmpty ? position : position - colliders[node].position
            holder.orientation = orientation
            holder.scale = SIMD3(repeating: animator.breathScale(node: node, time: frame.time))
        }
    }

    private static func castShadows(_ entity: Entity) {
        if entity.components.has(ModelComponent.self) {
            entity.components.set(GroundingShadowComponent(castsShadow: true))
        }
        entity.children.forEach { castShadows($0) }
    }

    private static func marker(in parent: Entity, at position: SIMD3<Float>) -> Entity {
        let marker = Entity()
        marker.position = position
        parent.addChild(marker)
        return marker
    }
}
