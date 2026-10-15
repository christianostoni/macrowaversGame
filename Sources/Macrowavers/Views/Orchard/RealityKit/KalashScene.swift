import RealityKit
import simd
import UIKit

/// The kalash: drag it anywhere, drop the fruit's orbs into it.
struct KalashComponent: Component {}

/// The kalash drawn in RealityKit: a brass pot the player keeps at their side (placed once by the right hip, it
/// stays where it is dropped), the orbs resting above its mouth and the blue spell they fuse into.
/// `Kalash.usdz` from the bundle when the design team delivers one, otherwise drawn in code.
/// Origin at the centre of its base.
@MainActor
final class KalashRig {
    static let name = "Kalash"
    /// Height of the pot (m).
    static let height: Float = 0.15

    let root = Entity()
    /// Centre of the mouth: where the orbs drop in.
    let mouth = Entity()
    /// Where the blue spell forms, above the mouth.
    let spellAnchor = Entity()
    let spell: Entity
    /// Ring of light around the mouth: an orb is close enough to drop, or the kalash is full and ready.
    private let glow: Entity
    /// Placed by the player's right hip (once, when the world appears).
    var isPlaced = false

    /// Height of the mouth above the base (m).
    private let mouthHeight: Float

    private init(body: Entity, mouthHeight: Float) {
        self.mouthHeight = mouthHeight
        spell = Self.makeSpell()
        glow = Self.makeGlow(mouthHeight: mouthHeight)
        root.name = Self.name
        root.addChild(body)
        mouth.position = SIMD3(0, mouthHeight, 0)
        root.addChild(mouth)
        spellAnchor.position = SIMD3(0, mouthHeight + 0.15, 0)
        root.addChild(spellAnchor)
        spell.isEnabled = false
        spellAnchor.addChild(spell)
        glow.isEnabled = false
        root.addChild(glow)

        root.components.set(KalashComponent())
        root.components.set(CollisionComponent(shapes: [
            .generateBox(width: 0.14, height: mouthHeight + 0.03, depth: 0.14)
                .offsetBy(translation: SIMD3(0, (mouthHeight + 0.03) / 2, 0)),
        ]))
        root.components.set(InputTargetComponent())
        root.components.set(HoverEffectComponent())
    }

    static func make() async -> KalashRig {
        if let asset = try? await Entity(named: name, in: .main) {
            // Scaled to the kalash's height, base centre at the origin.
            let bounds = asset.visualBounds(relativeTo: nil)
            let scale = bounds.extents.y > 0 ? height / bounds.extents.y : 1
            let body = Entity()
            asset.position = -SIMD3(bounds.center.x, bounds.min.y, bounds.center.z)
            body.addChild(asset)
            body.scale = SIMD3(repeating: scale)
            return KalashRig(body: body, mouthHeight: height)
        }
        return KalashRig(body: makeBody(), mouthHeight: mouthHeight)
    }

    // MARK: - Orbs and spell

    /// Where a stored orb rests (root space): three slots in a triangle just above the mouth. While the spell
    /// forms the orbs spiral up into it.
    func storedOrbPosition(slot: Int, spell: Kalash) -> SIMD3<Float> {
        let angle = Float(slot) * 2 * .pi / 3 + .pi / 2
        let rest = SIMD3<Float>(0.022 * cos(angle), mouthHeight + 0.015, 0.022 * sin(angle))
        guard spell.spell == .forming else { return rest }
        let progress = min(spell.stateTime / Kalash.formingDuration, 1)
        let eased = progress * progress * (3 - 2 * progress)
        let swirl = angle + progress * 4 * .pi
        let radius = 0.022 + 0.03 * sin(progress * .pi)
        let center = simd_mix(SIMD3(0, rest.y, 0), spellAnchor.position, SIMD3(repeating: eased))
        return center + SIMD3(radius * cos(swirl), 0, radius * sin(swirl)) * (1 - eased)
    }

    /// Size of a stored orb: small in its slot, shrinking into the spell while it forms.
    func storedOrbScale(spell: Kalash) -> Float {
        guard spell.spell == .forming else { return 0.45 }
        return 0.45 * (1 - min(spell.stateTime / Kalash.formingDuration, 1))
    }

    /// Lights the rim (`intensity` 0…1; 0 hides it).
    func setGlow(_ intensity: Float) {
        glow.isEnabled = intensity > 0
        guard intensity > 0 else { return }
        glow.components.set(OpacityComponent(opacity: intensity))
    }

    /// Puts the kalash by the player's right hip, a little in front so they see it when they look down.
    func place(viewer: (position: SIMD3<Float>, forward: SIMD3<Float>)) {
        var forward = viewer.forward
        forward.y = 0
        forward = simd_length(forward) > 1e-4 ? simd_normalize(forward) : SIMD3(0, 0, -1)
        let right = simd_cross(forward, SIMD3(0, 1, 0))
        var position = viewer.position + right * 0.25 + forward * 0.15
        // Pocket height: the base well below the eyes (standing or seated), never on the floor.
        position.y = max(viewer.position.y - 0.62, 0.4)
        root.position = position
        isPlaced = true
    }

    // MARK: - Drawing

    /// The brass pot: round belly, narrow neck, flared lip, a copper band and mango leaves at the mouth.
    private static func makeBody() -> Entity {
        let body = Entity()
        var brass = PhysicallyBasedMaterial()
        brass.baseColor = .init(tint: UIColor(red: 0.86, green: 0.62, blue: 0.24, alpha: 1))
        brass.metallic = 1.0
        brass.roughness = 0.28
        brass.faceCulling = .none
        if let pot = try? lathe(profile: potProfile) {
            body.addChild(ModelEntity(mesh: pot, materials: [brass]))
        }
        var copper = PhysicallyBasedMaterial()
        copper.baseColor = .init(tint: UIColor(red: 0.62, green: 0.25, blue: 0.14, alpha: 1))
        copper.metallic = 1.0
        copper.roughness = 0.35
        let bandProfile: [SIMD2<Float>] = [[0.0596, 0.054], [0.0628, 0.058], [0.0632, 0.062], [0.0626, 0.066], [0.0596, 0.07]]
        if let band = try? lathe(profile: bandProfile) {
            body.addChild(ModelEntity(mesh: band, materials: [copper]))
        }
        var leaf = PhysicallyBasedMaterial()
        leaf.baseColor = .init(tint: UIColor(red: 0.2, green: 0.5, blue: 0.16, alpha: 1))
        leaf.roughness = 0.6
        for index in 0..<5 {
            let angle = Float(index) / 5 * 2 * .pi
            let model = ModelEntity(mesh: .generateBox(width: 0.014, height: 0.05, depth: 0.002, cornerRadius: 0.0009),
                                    materials: [leaf])
            model.position = SIMD3(0, 0.022, 0)
            let pivot = Entity()
            pivot.position = SIMD3(0.04 * cos(angle), mouthHeight - 0.006, 0.04 * sin(angle))
            // Each leaf leans outwards, over the lip.
            pivot.orientation = simd_quatf(angle: 0.9, axis: SIMD3(sin(angle), 0, -cos(angle)))
            pivot.addChild(model)
            body.addChild(pivot)
        }
        return body
    }

    /// Height of the drawn pot's mouth (m).
    private static let mouthHeight: Float = 0.147

    /// Outline of the pot, (radius, height) from the base up to the lip and a little down inside it.
    private static let potProfile: [SIMD2<Float>] = [
        [0, 0], [0.03, 0], [0.036, 0.003], [0.031, 0.011], [0.039, 0.02], [0.05, 0.032], [0.058, 0.046],
        [0.0612, 0.06], [0.0592, 0.075], [0.052, 0.09], [0.04, 0.103], [0.03, 0.112], [0.0262, 0.12],
        [0.0272, 0.128], [0.034, 0.136], [0.044, 0.142], [0.048, 0.146], [0.046, 0.149], [0.04, 0.146],
        [0.03, 0.138], [0.024, 0.128], [0.022, 0.118],
    ]

    private static func makeGlow(mouthHeight: Float) -> Entity {
        let ring = (0...12).map { index -> SIMD2<Float> in
            let angle = Float(index) / 12 * 2 * .pi
            return [0.047 + 0.006 * cos(angle), mouthHeight + 0.002 + 0.006 * sin(angle)]
        }
        let glow = Entity()
        var material = UnlitMaterial(color: UIColor(red: 0.55, green: 0.85, blue: 1, alpha: 1))
        material.blending = .transparent(opacity: .init(floatLiteral: 0.8))
        if let mesh = try? lathe(profile: ring) {
            glow.addChild(ModelEntity(mesh: mesh, materials: [material]))
        }
        return glow
    }

    /// The blue spell: a glowing blue orb with a halo and sparkles.
    private static func makeSpell() -> Entity {
        let spell = Entity()
        spell.name = "BlueSpell"
        var core = PhysicallyBasedMaterial()
        core.baseColor = .init(tint: UIColor(red: 0.3, green: 0.6, blue: 1, alpha: 1))
        core.emissiveColor = .init(color: UIColor(red: 0.25, green: 0.55, blue: 1, alpha: 1))
        core.emissiveIntensity = 3
        core.roughness = 0.15
        spell.addChild(ModelEntity(mesh: .generateSphere(radius: 0.035), materials: [core]))
        var halo = UnlitMaterial(color: UIColor(red: 0.45, green: 0.75, blue: 1, alpha: 1))
        halo.blending = .transparent(opacity: .init(floatLiteral: 0.25))
        spell.addChild(ModelEntity(mesh: .generateSphere(radius: 0.055), materials: [halo]))

        var sparkles = ParticleEmitterComponent()
        sparkles.emitterShape = .sphere
        sparkles.emitterShapeSize = SIMD3(repeating: 0.04)
        sparkles.mainEmitter.birthRate = 40
        sparkles.mainEmitter.lifeSpan = 0.8
        sparkles.mainEmitter.size = 0.003
        sparkles.speed = 0.04
        sparkles.mainEmitter.color = .constant(.single(UIColor(red: 0.6, green: 0.85, blue: 1, alpha: 1)))
        spell.components.set(sparkles)
        return spell
    }

    /// Surface of revolution around Y of `profile` ((radius, height) points), with smooth normals.
    private static func lathe(profile: [SIMD2<Float>], segments: Int = 48) throws -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        for (index, point) in profile.enumerated() {
            let tangent = profile[min(index + 1, profile.count - 1)] - profile[max(index - 1, 0)]
            let flat = simd_length(tangent) > 1e-6 ? simd_normalize(SIMD2(tangent.y, -tangent.x)) : SIMD2<Float>(0, -1)
            for segment in 0...segments {
                let angle = Float(segment) / Float(segments) * 2 * .pi
                positions.append(SIMD3(point.x * cos(angle), point.y, point.x * sin(angle)))
                normals.append(SIMD3(flat.x * cos(angle), flat.y, flat.x * sin(angle)))
            }
        }
        var indices: [UInt32] = []
        let columns = segments + 1
        for row in 0..<(profile.count - 1) {
            for column in 0..<segments {
                let first = UInt32(row * columns + column)
                let above = first + UInt32(columns)
                indices += [first, first + 1, above, first + 1, above + 1, above]
            }
        }
        var descriptor = MeshDescriptor(name: "lathe")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}

// MARK: - System

extension OrchardSystem {
    /// Places the kalash, lights it, reads the twist that casts the spell and flies the spell to the dragon.
    @MainActor
    static func updateKalash(_ orchard: inout OrchardComponent, root: Entity, deltaTime: Float) {
        let kalash = orchard.kalash
        let viewModel = orchard.viewModel
        // A moment after the world appears, so head tracking is running.
        if !kalash.isPlaced && orchard.time > 0.3 {
            kalash.place(viewer: orchard.viewer.viewerPose())
        }
        // Once the dragon has left the island the kalash must not take the grabs meant for its knot.
        kalash.root.components[InputTargetComponent.self]?.isEnabled = viewModel.isDragonOnIsland

        let mouth = kalash.mouth.position(relativeTo: nil)
        let isOrbNear = orchard.orbs.contains { id, orb in
            viewModel.orbs.indices.contains(id) && viewModel.orbs[id] == .held
                && simd_distance(orb.position(relativeTo: nil), mouth) < OrchardComponent.kalashDropRadius
        }
        if isOrbNear {
            kalash.setGlow(1)
        } else if viewModel.kalash.spell == .ready {
            kalash.setGlow(0.45 + 0.35 * sin(orchard.time * 3))
        } else {
            kalash.setGlow(0)
        }

        detectTwist(&orchard, mouth: mouth)
        updateSpell(orchard: orchard, root: root, deltaTime: deltaTime)
    }

    /// Thumb and index pinched, the wrist rolls, eyes on the full kalash: the spell is cast.
    @MainActor
    private static func detectTwist(_ orchard: inout OrchardComponent, mouth: SIMD3<Float>) {
        let viewModel = orchard.viewModel
        defer {
            // Steps of 10 %: the label moves without SwiftUI redrawing every frame.
            let progress = (orchard.twist.progress * 10).rounded(.down) / 10
            if viewModel.twistProgress != progress { viewModel.twistProgress = progress }
        }
        guard viewModel.kalash.spell == .ready else {
            orchard.twist.reset()
            return
        }
        let viewer = orchard.viewer.viewerPose()
        let isLooking = TwistDetector.isLooking(from: viewer.position, forward: viewer.forward, at: mouth)
        for sample in orchard.hands.samples.values where orchard.twist.process(sample, isLooking: isLooking) {
            viewModel.castSpell()
            return
        }
    }

    @MainActor
    private static func updateSpell(orchard: OrchardComponent, root: Entity, deltaTime: Float) {
        let spell = orchard.kalash.spell
        let state = orchard.viewModel.kalash
        let pulse = 1 + 0.1 * sin(orchard.time * 5)
        switch state.spell {
        case .gathering, .ready, .delivered:
            spell.isEnabled = false
        case .forming:
            attach(spell, to: orchard.kalash.spellAnchor, preservingWorldTransform: false)
            spell.position = .zero
            spell.isEnabled = true
            let progress = min(state.stateTime / Kalash.formingDuration, 1)
            spell.setScale(SIMD3(repeating: max(progress * progress, 0.01)), relativeTo: nil)
        case .formed:
            attach(spell, to: orchard.kalash.spellAnchor, preservingWorldTransform: false)
            spell.isEnabled = true
            spell.position = SIMD3(0, 0.012 * sin(orchard.time * 2), 0)
            spell.setScale(SIMD3(repeating: pulse), relativeTo: nil)
        case .flying:
            attach(spell, to: root, preservingWorldTransform: true)
            spell.isEnabled = true
            let offset = orchard.deliveryTarget.position(relativeTo: root) - spell.position
            let distance = simd_length(offset)
            if distance < 0.05 {
                spell.isEnabled = false
                orchard.viewModel.spellDelivered()
            } else {
                spell.position += offset / distance * min(distance, OrchardComponent.spellSpeed * deltaTime)
                spell.setScale(SIMD3(repeating: pulse), relativeTo: nil)
            }
        }
    }
}
