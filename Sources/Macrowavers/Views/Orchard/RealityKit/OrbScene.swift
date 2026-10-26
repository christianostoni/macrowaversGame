import RealityKit
import simd
import UIKit

// MARK: - Orbs

extension OrchardSystem {
    /// Moves every fruit's orb for its state: sealed in the fruit, rising out of it, flying to the orbit in front of the
    /// player and orbiting there (diving into the flask when the elixir is brewed), spent.
    @MainActor
    static func updateOrbs(orchard: OrchardComponent, root: Entity, deltaTime: Float) {
        let viewModel = orchard.viewModel
        let pulse = 1 + 0.08 * sin(orchard.time * 4)
        let follow = 1 - exp(-deltaTime * 10)
        for fruit in orchard.fruits {
            let id = fruit.fruit.id
            guard let orb = orchard.orbs[id], viewModel.orbs.indices.contains(id) else { continue }
            if orb.isEnabled { OrchardSceneBuilder.spinGem(orb, time: orchard.time, phase: Float(id) * 1.3) }
            let isFocused = id == viewModel.focusedFruitID
            switch viewModel.orbs[id] {
            case .sealed:
                resetJourney(orb)
                showSealed(orb, in: fruit, isVisible: isFocused && fruit.showsSealedOrb)
            case .revealed:
                showRevealed(orb, above: fruit, viewModel: viewModel, time: orchard.time, follow: follow)
                orb.setScale(SIMD3(repeating: pulse), relativeTo: nil)
            case .orbiting(let slot):
                showOrbiting(orb, slot: slot, orchard: orchard, root: root, deltaTime: deltaTime)
                let held = orb.components[OrbComponent.self]?.heldScale ?? 1
                let scale = max(pulse * viewModel.elixir.ingredientScale(slot: slot) * held, 0.001)
                orb.setScale(SIMD3(repeating: scale), relativeTo: nil)
            case .spent:
                orb.isEnabled = false
                setEmitting(orb, OrchardSceneBuilder.orbTrailName, false)
            }
        }
    }

    /// Locked in the fruit: visible only between the open apple's slices, never tappable.
    @MainActor
    private static func showSealed(_ orb: Entity, in fruit: OrchardFruit, isVisible: Bool) {
        orb.isEnabled = isVisible
        orb.components[InputTargetComponent.self]?.isEnabled = false
        guard isVisible else { return }
        attach(orb, to: fruit.orbAnchor, preservingWorldTransform: false)
        orb.position = .zero
        orb.setScale(SIMD3(repeating: 0.7), relativeTo: nil)
    }

    /// Rises out of the opened fruit and floats above it; once out it can be tapped into orbit (it goes by itself
    /// a moment later). Sent back to the tree before that, it rises above its fruit on the branch.
    @MainActor
    private static func showRevealed(_ orb: Entity, above fruit: OrchardFruit, viewModel: OrchardViewModel,
                                     time: Float, follow: Float) {
        attach(orb, to: fruit.orbAnchor, preservingWorldTransform: true)
        orb.isEnabled = true
        let rise = min(viewModel.orbRevealTimes[fruit.fruit.id] / OrchardViewModel.orbRiseDuration, 1)
        let eased = rise * rise * (3 - 2 * rise)
        let target = SIMD3<Float>(0, fruit.orbHeight(viewModel: viewModel) * eased + 0.01 * sin(time * 2), 0)
        orb.position = simd_mix(orb.position, target, SIMD3(repeating: follow))
        orb.components[InputTargetComponent.self]?.isEnabled = rise >= 1 && viewModel.isDragonOnIsland
    }

    /// Flies from its fruit to its slot on the orbit (an eased arc), takes its ingredient's colour and leaves a
    /// trail; then goes round with the others. While the elixir is brewed it dives into the flask's neck.
    @MainActor
    private static func showOrbiting(_ orb: Entity, slot: Int, orchard: OrchardComponent, root: Entity,
                                     deltaTime: Float) {
        guard var journey = orb.components[OrbComponent.self] else { return }
        let viewModel = orchard.viewModel
        attach(orb, to: root, preservingWorldTransform: true)
        orb.isEnabled = true
        if journey.tintedSlot != slot {
            OrchardSceneBuilder.tint(orb, color: OrchardSceneBuilder.ingredientColor(slot: slot))
            journey.tintedSlot = slot
        }

        let elixir = viewModel.elixir
        let dive = elixir.state == .fusing || elixir.state == .brewed ? elixir.diveProgress(slot: slot) : 0
        // Into the flask: the glow (a 12 cm quad, wider than the neck, drawn without depth) and the sparks would show
        // through the glass, so they are gone before the gem drops into the neck. The gem itself is opaque.
        setEmitting(orb, OrchardSceneBuilder.orbTrailName, dive < Self.diveSparksStop)
        setEmitting(orb, OrchardSceneBuilder.orbGlintsName, dive < Self.diveSparksStop)
        let glow = 1 - Elixir.smoothstep(from: Self.diveGlowFade.lowerBound, to: Self.diveGlowFade.upperBound, dive)
        orb.findEntity(named: OrchardSceneBuilder.orbHaloName)?.scale = SIMD3(repeating: max(glow, 0.001))
        // Held while the elixir is brewed (a snap with the other hand): it lets go and dives with the others.
        if journey.isHeld, !elixir.letsIngredientsBeHeld {
            journey.isHeld = false
            journey.joinStart = nil
            journey.joinElapsed = 0
        }
        // Pinch an ingredient to drag and turn it, or tap it to brew the elixir (without hand tracking); never while
        // a fruit is close or the dragon is away.
        orb.components[InputTargetComponent.self]?.isEnabled = elixir.letsIngredientsBeHeld
            && viewModel.focusedFruitID == nil && viewModel.isDragonOnIsland
        guard !journey.isHeld else {
            orb.components.set(journey)
            return
        }
        // Back from the hand: it turns upright again and takes back its own size.
        let settle = 1 - exp(-deltaTime * 4)
        orb.orientation = simd_slerp(orb.orientation, simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)), settle)
        journey.heldScale += (1 - journey.heldScale) * settle
        let target: SIMD3<Float>
        if elixir.state == .fusing || elixir.state == .brewed {
            let neck = orchard.elixir.neck(relativeTo: root)
            target = orchard.orbit.divePosition(slot: slot, progress: elixir.diveProgress(slot: slot),
                                                neckTop: neck.top, neckBase: neck.base)
        } else {
            target = orchard.orbit.point(slot: slot)
        }
        let start = journey.joinStart ?? orb.position
        journey.joinStart = start
        journey.joinElapsed += deltaTime
        let join = min(journey.joinElapsed / OrbComponent.joinDuration, 1)
        let eased = Elixir.smootherstep(join)
        // Out of the fruit it lifts a little before settling into the orbit: an arc, not a slide.
        orb.position = simd_mix(start, target, SIMD3(repeating: eased)) + SIMD3(0, 0.2 * sin(.pi * join), 0)
        orb.components.set(journey)
    }

    /// Back in its fruit (the game restarted): the neutral colour again, ready for a new journey.
    @MainActor
    private static func resetJourney(_ orb: Entity) {
        guard var journey = orb.components[OrbComponent.self], journey.tintedSlot != nil else { return }
        OrchardSceneBuilder.tint(orb, color: OrchardSceneBuilder.sealedColor)
        journey = OrbComponent(fruitID: journey.fruitID)
        orb.components.set(journey)
        setEmitting(orb, OrchardSceneBuilder.orbTrailName, false)
        setEmitting(orb, OrchardSceneBuilder.orbGlintsName, true)
        orb.findEntity(named: OrchardSceneBuilder.orbHaloName)?.scale = SIMD3(repeating: 1)
    }

    /// Share of its dive (`Elixir.diveProgress`) over which an ingredient's glow fades: gone well before the neck.
    static let diveGlowFade: ClosedRange<Float> = 0.45...0.75
    /// Its trail and glints stop here, while it is still above the flask.
    static let diveSparksStop: Float = 0.5

    /// Starts or stops one of the orb's particle emitters (`orbTrailName`, `orbGlintsName`).
    @MainActor
    private static func setEmitting(_ orb: Entity, _ name: String, _ isEmitting: Bool) {
        guard let entity = orb.findEntity(named: name),
              var emitter = entity.components[ParticleEmitterComponent.self], emitter.isEmitting != isEmitting else {
            return
        }
        emitter.isEmitting = isEmitting
        entity.components.set(emitter)
    }

    @MainActor
    static func attach(_ entity: Entity, to parent: Entity, preservingWorldTransform: Bool) {
        guard entity.parent !== parent else { return }
        entity.setParent(parent, preservingWorldTransform: preservingWorldTransform)
    }
}

// MARK: - Building

extension OrchardSceneBuilder {
    static let orbSpinName = "OrbSpin"
    static let orbHaloName = "OrbHalo"
    static let orbGlintsName = "OrbGlints"
    static let orbTrailName = "OrbTrail"
    /// The design team's gem (`Assets/Blender/ingredient-gem`): 6 cm tall, origin at its centre, long axis up.
    static let gemAssetName = "IngredientGem"
    /// Turns per second of the gem around its long axis: its facets catch the light one by one.
    static let gemSpinSpeed: Float = 0.2
    /// Width of the glow around the gem (m).
    static let glowSize: Float = 0.12

    /// Warm white: an orb not found yet.
    static let sealedColor = UIColor(red: 1, green: 0.9, blue: 0.7, alpha: 1)

    /// The glow drawn behind the gem, the gem over it.
    private static let orbSortGroup = ModelSortGroup()

    /// Colour of each ingredient once it orbits the player (`Elixir.ingredientColors`).
    static func ingredientColor(slot: Int) -> UIColor {
        color(Elixir.ingredientColor(slot: slot))
    }

    static func color(_ rgb: SIMD3<Float>, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: alpha)
    }

    /// The orb found in every fruit, an ingredient of the elixir: the design team's crystal gem, spinning slowly,
    /// with a soft glow that always faces the player, glints sparkling around it and a trail of sparks while it
    /// orbits. Origin at its centre. Cloned for every fruit. Without its asset, a sphere stands in for the gem.
    @MainActor
    static func makeOrbTemplate() async -> Entity {
        let orb = Entity()
        let spin = Entity()
        spin.name = orbSpinName
        orb.addChild(spin)
        if let gem = try? await Entity(named: gemAssetName, in: .main) {
            spin.addChild(gem)
        } else {
            print("⚠️ \(gemAssetName).usdz not found: a sphere stands in for the ingredient gem")
            spin.addChild(ModelEntity(mesh: .generateSphere(radius: 0.025), materials: []))
        }
        for model in models(in: spin) {
            model.components.set(ModelSortGroupComponent(group: orbSortGroup, order: 1))
        }

        let halo = ModelEntity(mesh: .generatePlane(width: glowSize, height: glowSize), materials: [])
        halo.name = orbHaloName
        halo.components.set(BillboardComponent())
        halo.components.set(ModelSortGroupComponent(group: orbSortGroup, order: 0))
        orb.addChild(halo)

        let glints = Entity()
        glints.name = orbGlintsName
        var sparkle = ParticleEmitterComponent()
        sparkle.emitterShape = .sphere
        sparkle.emitterShapeSize = SIMD3(repeating: 0.022)
        sparkle.speed = 0.002
        sparkle.mainEmitter.birthRate = 7
        sparkle.mainEmitter.lifeSpan = 0.45
        sparkle.mainEmitter.size = 0.004
        sparkle.mainEmitter.opacityCurve = .quickFadeInOut
        sparkle.mainEmitter.blendMode = .additive
        glints.components.set(sparkle)
        orb.addChild(glints)

        let trail = Entity()
        trail.name = orbTrailName
        var sparks = ParticleEmitterComponent()
        sparks.emitterShape = .sphere
        sparks.emitterShapeSize = SIMD3(repeating: 0.015)
        sparks.speed = 0.005
        sparks.isEmitting = false
        sparks.mainEmitter.birthRate = 35
        sparks.mainEmitter.lifeSpan = 0.6
        sparks.mainEmitter.size = 0.003
        trail.components.set(sparks)
        orb.addChild(trail)
        glowTexture = await makeGlowTexture()
        tint(orb, color: sealedColor)

        // Generous: it may be tapped while it moves. No hover effect: visionOS would light up every mesh under the
        // orb, the glow's square quad too, a box around the gem when it is looked at or taken.
        orb.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.05)]))
        orb.components.set(InputTargetComponent.disabled)
        return orb
    }

    /// Colours the gem, its glow, its glints and its trail.
    @MainActor
    static func tint(_ orb: Entity, color: UIColor) {
        if let spin = orb.findEntity(named: orbSpinName) {
            let material = gemMaterial(color: color)
            for model in models(in: spin) {
                // One material per part of the mesh (the stand-in sphere starts with none).
                let count = max(model.components[ModelComponent.self]?.materials.count ?? 1, 1)
                model.components[ModelComponent.self]?.materials = Array(repeating: material, count: count)
            }
        }
        if let halo = orb.findEntity(named: orbHaloName) as? ModelEntity {
            halo.model?.materials = [glowMaterial(color: color)]
        }
        for name in [orbGlintsName, orbTrailName] {
            if let emitter = orb.findEntity(named: name), var particles = emitter.components[ParticleEmitterComponent.self] {
                particles.mainEmitter.color = .constant(.single(color))
                emitter.components.set(particles)
            }
        }
    }

    /// Turns the gem slowly around its long axis (each orb starts at its own angle).
    @MainActor
    static func spinGem(_ orb: Entity, time: Float, phase: Float) {
        orb.findEntity(named: orbSpinName)?.orientation = simd_quatf(angle: 2 * .pi * gemSpinSpeed * time + phase,
                                                                      axis: SIMD3(0, 1, 0))
    }

    /// The design team's crystal, tinted and opaque: a see-through gem looked washed out in the room, and its
    /// transparent faces could sort wrongly against the flask's glass. What keeps it a gem is its flat facets, each
    /// lit differently as it spins (no emission strong enough to light them all the same). Shine: full specular and
    /// a clear coat for the highlights. The glow is the billboard behind.
    private static func gemMaterial(color: UIColor) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = 0.15
        material.metallic = 0.0
        material.specular = .init(floatLiteral: 1)
        material.clearcoat = .init(floatLiteral: 1)
        material.clearcoatRoughness = .init(floatLiteral: 0.03)
        material.emissiveColor = .init(color: color)
        material.emissiveIntensity = 0.5
        return material
    }

    /// A soft round light behind the gem, brightest at its centre. Without the texture, a faint disc. It writes no
    /// depth: its quad is invisible at the corners, but writing depth there it hid the flask's glass behind it (a
    /// see-through square crossing the flask).
    @MainActor
    private static func glowMaterial(color: UIColor) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        if let glowTexture {
            material.color = .init(tint: color, texture: .init(glowTexture))
            material.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        } else {
            material.blending = .transparent(opacity: .init(floatLiteral: 0.2))
        }
        material.writesDepth = false
        return material
    }

    /// Shared by every orb's glow: made once, with the first template.
    @MainActor private static var glowTexture: TextureResource?

    /// White at the centre, fading to nothing at the edge (premultiplied alpha), so the tint gives its colour.
    @MainActor
    private static func makeGlowTexture() async -> TextureResource? {
        if let glowTexture { return glowTexture }
        let size = 128
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: space,
                                        colors: [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                                                 CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.35),
                                                 CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
                                        locations: [0, 0.3, 1]) else { return nil }
        let centre = CGPoint(x: size / 2, y: size / 2)
        context.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre,
                                   endRadius: CGFloat(size) / 2, options: [])
        guard let image = context.makeImage() else { return nil }
        return try? await TextureResource(image: image, options: .init(semantic: .color))
    }

    @MainActor
    private static func models(in entity: Entity) -> [Entity] {
        (entity.components.has(ModelComponent.self) ? [entity] : []) + entity.children.flatMap { models(in: $0) }
    }
}
