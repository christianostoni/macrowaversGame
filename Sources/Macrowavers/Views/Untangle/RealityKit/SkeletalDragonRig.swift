import Foundation
import RealityKit
import simd

/// Rig for the design team's real asset. Used automatically when `DragonBody` is in the bundle.
///
/// - `DragonBody` (USDZ / Reality Composer Pro): skinned mesh with a chain of joints
///   `spine_00` (neck, near the head) … `spine_NN` (tail tip), each a child of the previous one.
///   The spine is driven by the simulation every frame: it must NOT have animations on the spine.
///   Optional wings: joints `wing_L` / `wing_R` (children of a shoulder vertebra), opened by code
///   rotating around the local axis `Asset.wingFlareAxis`.
/// - `DragonHead` (optional): separate head with the animations (see `clipName`) and two empty entities
///   `nostrils` and `mouth` where smoke and fire come out. Origin at the neck joint, snout towards +Z.
///   When missing, the animations of `DragonBody` are used.
///
/// ⚠️ Tested only with the temporary Sketchfab asset: check again with the design team's first export.
@MainActor
final class SkeletalDragonRig: DragonRig {
    enum Asset {
        static let body = "DragonBody"
        static let head = "DragonHead"
        static let spineJointPrefix = "spine_"
        static let leftWingJoint = "wing_L"
        static let rightWingJoint = "wing_R"
        /// Local axis the wing bone rotates around to spread.
        static let wingFlareAxis = SIMD3<Float>(0, 0, 1)
        /// Stretch of neck (m) leaving the back of the head in the head's direction before reaching the simulated body.
        static let neckBlendLength: Float = 0.18
        /// Curve points between two simulated nodes: the spine has more bones than nodes, without them it would follow the corners.
        static let curveSubdivisions = 4
        /// Body radius of the asset once scaled to the simulated length (`THICKNESS` in make_dragon_asset.py).
        /// The rig thickens the body to `TangleConfig.radius`, so what the player sees matches the collisions.
        static let modelledRadius: Float = 0.03
    }

    /// Names of the animations expected in the asset: first the one of the current move, then the mood's.
    static func clipName(for mood: DragonMood, action: DragonAction?) -> String {
        switch action {
        case .rearUp: return "roar"
        case .turn: return "turn"
        case .tailLash: return "lash"
        case .coil: return "coil"
        case nil: break
        }
        switch mood {
        case .calm: return "idle"
        case .annoyed: return "annoyed"
        case .restless: return "restless"
        case .wriggling: return "wriggle"
        case .free: return "happy"
        }
    }

    let entity = Entity()

    private var animator: DragonLifeAnimator
    private let model: ModelEntity
    private let head: Entity?
    /// Follows the head (asset or, when missing, an empty entity): smoke, fire and sounds come out of it.
    private let headAnchor: Entity
    private let animatedEntity: Entity
    private let clips: [String: AnimationResource]
    private var playingClip: String?
    private let effects = DragonEffects()
    /// Wing joints (index, side: -1 left, +1 right).
    private let wingJoints: [(index: Int, side: Float)]

    private let spineIndices: [Int]
    private let bindTransforms: [Transform]
    /// Transform (model space) of the parent of `spine_00`: considered fixed.
    private let chainParentMatrix: float4x4
    /// Orientation of `spine_00` in the rest pose (model space): keeps the artist's "roll".
    private let bindRootOrientation: simd_quatf
    /// Direction of each bone in its own local space (towards the child joint).
    private let boneAxes: [SIMD3<Float>]
    /// Distance of each joint from `spine_00` along the chain (model units).
    private let arcLengths: [Float]
    /// How much thicker than the asset the body is drawn (uniform scale of `spine_00`, inherited by the chain).
    private let thickness: Float

    static func load(config: TangleConfig) async -> SkeletalDragonRig? {
        guard let bodyRoot = try? await Entity(named: Asset.body, in: .main) else { return nil }
        guard let model = findSkinnedModel(in: bodyRoot) else {
            print("⚠️ \(Asset.body): no ModelEntity with a skeleton, using the placeholder dragon.")
            return nil
        }
        let head = try? await Entity(named: Asset.head, in: .main)
        return SkeletalDragonRig(config: config, bodyRoot: bodyRoot, model: model, head: head)
    }

    private init?(config: TangleConfig, bodyRoot: Entity, model: ModelEntity, head: Entity?) {
        let names = model.jointNames
        let spine = names.indices
            .filter { Self.lastComponent(names[$0]).hasPrefix(Asset.spineJointPrefix) }
            .sorted { Self.lastComponent(names[$0]) < Self.lastComponent(names[$1]) }
        guard spine.count >= 2 else {
            print("⚠️ \(Asset.body): needs at least 2 '\(Asset.spineJointPrefix)*' joints, found \(spine.count).")
            return nil
        }

        animator = DragonLifeAnimator(config: config)
        thickness = max(config.radius / Asset.modelledRadius, 0.1)
        self.model = model
        self.head = head
        spineIndices = spine
        let bind = model.jointTransforms
        bindTransforms = bind

        let parentPath = Self.parentPath(names[spine[0]])
        let parentMatrix = Self.modelMatrix(path: parentPath, names: names, bind: bind)
        chainParentMatrix = parentMatrix
        bindRootOrientation = simd_quatf(parentMatrix) * bind[spine[0]].rotation

        // Offset of each joint from the previous one: gives the bones' length and direction.
        let offsets = spine.dropFirst().map { bind[$0].translation }
        var lengths: [Float] = [0]
        for offset in offsets { lengths.append(lengths.last! + simd_length(offset)) }
        arcLengths = lengths
        let spineLength = lengths.last!
        var axes = offsets.map { simd_length($0) > 1e-6 ? simd_normalize($0) : SIMD3<Float>(0, 1, 0) }
        axes.append(axes.last!)
        boneAxes = axes

        let animated = head ?? bodyRoot
        animatedEntity = animated
        clips = Self.collectClips(from: animated)

        wingJoints = names.indices.compactMap { index in
            switch Self.lastComponent(names[index]) {
            case Asset.leftWingJoint: (index, -1)
            case Asset.rightWingJoint: (index, 1)
            default: nil
            }
        }

        entity.name = "SkeletalDragon"
        entity.addChild(bodyRoot)
        // The head sits inside a container: the code moves the container and never overwrites the
        // transform of the asset's root (e.g. the Z-up → Y-up rotation added by Blender's export).
        let anchor = Entity()
        if let head { anchor.addChild(head) }
        headAnchor = anchor
        entity.addChild(anchor)
        let nostrils = anchor.findEntity(named: "nostrils") ?? Self.marker(in: anchor, at: SIMD3(0, 0.01, 0.08))
        let mouth = anchor.findEntity(named: "mouth") ?? Self.marker(in: anchor, at: SIMD3(0, -0.01, 0.08))
        effects.attach(nostrils: nostrils, mouth: mouth, voice: anchor)

        // Scales the asset so the spine is as long as the simulated body.
        let measured = simd_length(entity.convert(position: SIMD3(spineLength, 0, 0), from: model)
                                   - entity.convert(position: .zero, from: model))
        let simulatedLength = config.segmentLength * Float(config.nodeCount - 1)
        if measured > 1e-6 {
            let factor = simulatedLength / measured
            bodyRoot.scale *= factor
            // The head grows with the neck: no seam where they meet.
            head?.scale *= factor * thickness
        }
    }

    func update(_ frame: DragonFrame, deltaTime: Float) {
        animator.update(frame, deltaTime: deltaTime)
        let head = animator.pose.headOrientation
        let visual = Self.neckFollowingHead(animator.visualPositions(frame), headOrientation: head)

        headAnchor.position = visual[0]
        headAnchor.orientation = head
        playClip(named: Self.clipName(for: frame.mood, action: frame.action), loops: frame.action == nil)
        effects.update(pose: animator.pose, frame: frame)

        var transforms = model.jointTransforms
        poseSpine(along: Self.smoothed(visual).map { model.convert(position: $0, from: entity) }, transforms: &transforms)
        poseWings(&transforms)
        model.jointTransforms = transforms
    }

    private func poseWings(_ transforms: inout [Transform]) {
        let pose = animator.pose
        let angle = -0.2 + 1.2 * pose.wingFlare + pose.wingFlap
        for (index, side) in wingJoints {
            transforms[index].rotation = bindTransforms[index].rotation
                * simd_quatf(angle: side * angle, axis: Asset.wingFlareAxis)
            // The wings sit on the thicker body but keep their size.
            transforms[index].scale = bindTransforms[index].scale / thickness
        }
    }

    // MARK: - Spine driven by the simulation

    private func poseSpine(along curve: [SIMD3<Float>], transforms: inout [Transform]) {
        let targets = arcLengths.map { Self.point(on: curve, atArcLength: $0) }
        var previousOrientation = bindRootOrientation

        for (k, jointIndex) in spineIndices.enumerated() {
            let next = k + 1 < targets.count ? targets[k + 1] : targets[k] + (targets[k] - targets[k - 1])
            let direction = next - targets[k]
            guard simd_length(direction) > 1e-6 else { continue }

            // Parallel transport: rotates as little as possible relative to the previous bone (no twisting).
            let currentAxis = previousOrientation.act(boneAxes[k])
            let orientation = simd_quatf(from: simd_normalize(currentAxis), to: simd_normalize(direction)) * previousOrientation

            var local = bindTransforms[jointIndex]
            if k == 0 {
                let world = float4x4(translation: targets[0]) * float4x4(orientation)
                let relative = Transform(matrix: chainParentMatrix.inverse * world)
                local.translation = relative.translation
                local.rotation = relative.rotation
                // Thicker body: the whole chain inherits this uniform scale...
                local.scale = bindTransforms[jointIndex].scale * thickness
            } else {
                // ...and every bone keeps the asset's length (its offset is shortened by the inherited scale):
                // the skin swells around the spine, the body does not get longer. Only the rotation changes.
                local.translation = bindTransforms[jointIndex].translation / thickness
                local.rotation = previousOrientation.inverse * orientation
            }
            transforms[jointIndex] = local
            previousOrientation = orientation
        }
    }

    /// The head is a rigid piece: if it turns relative to the neck the seam shows. So the first stretch of
    /// neck leaves the back of the head opposite to the snout and blends gradually into the simulated body.
    /// When the head looks up it rises a little, so the neck does not sink below the play area.
    private static func neckFollowingHead(_ points: [SIMD3<Float>], headOrientation: simd_quatf) -> [SIMD3<Float>] {
        guard points.count > 1 else { return points }
        let blendLength = Asset.neckBlendLength
        let back = headOrientation.act(SIMD3(0, 0, -1))
        let start = points[0] + SIMD3(0, 0.5 * blendLength * max(0, -back.y), 0)
        var result = points
        result[0] = start
        var travelled: Float = 0
        for index in points.indices.dropFirst() {
            travelled += simd_length(points[index] - points[index - 1])
            guard travelled < blendLength else { break }
            let progress = travelled / blendLength
            let weight = progress * progress * (3 - 2 * progress)
            result[index] = simd_mix(start + back * travelled, points[index], SIMD3(repeating: weight))
        }
        return result
    }

    /// Catmull-Rom spline through the nodes: smooth curves instead of the polyline.
    private static func smoothed(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard points.count > 2 else { return points }
        let steps = Asset.curveSubdivisions
        var result: [SIMD3<Float>] = []
        result.reserveCapacity((points.count - 1) * steps + 1)
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            // Coefficients of the cubic polynomial of the p1 → p2 stretch.
            let c0 = 2 * p1
            let c1 = p2 - p0
            let c2 = 2 * p0 - 5 * p1 + 4 * p2 - p3
            let c3 = 3 * p1 - p0 - 3 * p2 + p3
            for step in 0..<steps {
                let along = Float(step) / Float(steps)
                result.append(0.5 * (c0 + c1 * along + c2 * (along * along) + c3 * (along * along * along)))
            }
        }
        result.append(points[points.count - 1])
        return result
    }

    // MARK: - Animations

    private func playClip(named name: String, loops: Bool) {
        guard name != playingClip else { return }
        playingClip = name
        guard let clip = clips[name] ?? clips["idle"] else { return }
        animatedEntity.playAnimation(loops ? clip.repeat() : clip, transitionDuration: 0.3, startsPaused: false)
    }

    private static func marker(in parent: Entity, at position: SIMD3<Float>) -> Entity {
        let marker = Entity()
        marker.position = position
        parent.addChild(marker)
        return marker
    }

    private static func collectClips(from root: Entity) -> [String: AnimationResource] {
        var result: [String: AnimationResource] = [:]
        // Reality Composer Pro: Animation Library.
        if let library = root.components[AnimationLibraryComponent.self] {
            for (name, animation) in library.animations { result[name] = animation }
        }
        // USDZ: named animations.
        for animation in root.availableAnimations {
            if let name = animation.name, result[name] == nil { result[name] = animation }
        }
        return result
    }

    // MARK: - Utilities

    private static func findSkinnedModel(in entity: Entity) -> ModelEntity? {
        if let model = entity as? ModelEntity, !model.jointNames.isEmpty { return model }
        for child in entity.children {
            if let found = findSkinnedModel(in: child) { return found }
        }
        return nil
    }

    private static func lastComponent(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    private static func parentPath(_ path: String) -> String {
        path.split(separator: "/").dropLast().joined(separator: "/")
    }

    /// Model-space transform of a joint, composing the rest pose of its ancestors.
    private static func modelMatrix(path: String, names: [String], bind: [Transform]) -> float4x4 {
        guard !path.isEmpty, let index = names.firstIndex(of: path) else { return matrix_identity_float4x4 }
        return modelMatrix(path: parentPath(path), names: names, bind: bind) * bind[index].matrix
    }

    /// Point on the polyline at a given distance from the start (extrapolates past the end).
    private static func point(on curve: [SIMD3<Float>], atArcLength target: Float) -> SIMD3<Float> {
        var travelled: Float = 0
        for i in 0..<(curve.count - 1) {
            let segment = simd_length(curve[i + 1] - curve[i])
            if travelled + segment >= target, segment > 0 {
                return curve[i] + (curve[i + 1] - curve[i]) * ((target - travelled) / segment)
            }
            travelled += segment
        }
        return curve.last!
    }
}

private extension float4x4 {
    init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4(translation, 1)
    }
}
