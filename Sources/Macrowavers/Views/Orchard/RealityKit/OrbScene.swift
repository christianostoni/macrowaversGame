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
                let scale = max(pulse * viewModel.elixir.ingredientScale(slot: slot), 0.001)
                orb.setScale(SIMD3(repeating: scale), relativeTo: nil)
            case .spent:
                orb.isEnabled = false
                setTrail(orb, isEmitting: false)
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
        setTrail(orb, isEmitting: true)

        let elixir = viewModel.elixir
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
        // Tap one to brew the elixir (without hand tracking); never while a fruit is close or the dragon is away.
        orb.components[InputTargetComponent.self]?.isEnabled = elixir.state == .ready
            && viewModel.focusedFruitID == nil && viewModel.isDragonOnIsland
    }

    /// Back in its fruit (the game restarted): the neutral colour again, ready for a new journey.
    @MainActor
    private static func resetJourney(_ orb: Entity) {
        guard var journey = orb.components[OrbComponent.self], journey.tintedSlot != nil else { return }
        OrchardSceneBuilder.tint(orb, color: OrchardSceneBuilder.sealedColor)
        journey = OrbComponent(fruitID: journey.fruitID)
        orb.components.set(journey)
        setTrail(orb, isEmitting: false)
    }

    @MainActor
    private static func setTrail(_ orb: Entity, isEmitting: Bool) {
        guard let trail = orb.findEntity(named: OrchardSceneBuilder.orbTrailName),
              var emitter = trail.components[ParticleEmitterComponent.self], emitter.isEmitting != isEmitting else {
            return
        }
        emitter.isEmitting = isEmitting
        trail.components.set(emitter)
    }

    @MainActor
    static func attach(_ entity: Entity, to parent: Entity, preservingWorldTransform: Bool) {
        guard entity.parent !== parent else { return }
        entity.setParent(parent, preservingWorldTransform: preservingWorldTransform)
    }
}

// MARK: - Building

extension OrchardSceneBuilder {
    static let orbCoreName = "OrbCore"
    static let orbHaloName = "OrbHalo"
    static let orbTrailName = "OrbTrail"

    /// Warm white: an orb not found yet.
    static let sealedColor = UIColor(red: 1, green: 0.9, blue: 0.7, alpha: 1)

    /// Colour of each ingredient once it orbits the player (`Elixir.ingredientColors`).
    static func ingredientColor(slot: Int) -> UIColor {
        color(Elixir.ingredientColor(slot: slot))
    }

    static func color(_ rgb: SIMD3<Float>, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: alpha)
    }

    /// The orb found in every fruit, an ingredient of the elixir: a glowing RealityKit sphere with a halo
    /// (placeholder), about 5 cm wide, origin at its centre, and a trail of sparks while it orbits. Cloned for
    /// every fruit.
    @MainActor
    static func makeOrbTemplate() -> Entity {
        let orb = Entity()
        let core = ModelEntity(mesh: .generateSphere(radius: 0.025), materials: [])
        core.name = orbCoreName
        orb.addChild(core)
        let halo = ModelEntity(mesh: .generateSphere(radius: 0.038), materials: [])
        halo.name = orbHaloName
        orb.addChild(halo)

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
        tint(orb, color: sealedColor)

        // Generous: it may be tapped while it moves.
        orb.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.05)]))
        orb.components.set(InputTargetComponent.disabled)
        orb.components.set(HoverEffectComponent())
        return orb
    }

    /// Colours the orb's core, halo and trail.
    @MainActor
    static func tint(_ orb: Entity, color: UIColor) {
        if let core = orb.findEntity(named: orbCoreName) as? ModelEntity {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: color)
            material.emissiveColor = .init(color: color)
            material.emissiveIntensity = 2.5
            material.metallic = 0.6
            material.roughness = 0.2
            core.model?.materials = [material]
        }
        if let halo = orb.findEntity(named: orbHaloName) as? ModelEntity {
            var material = UnlitMaterial(color: color)
            material.blending = .transparent(opacity: .init(floatLiteral: 0.25))
            halo.model?.materials = [material]
        }
        if let trail = orb.findEntity(named: orbTrailName), var sparks = trail.components[ParticleEmitterComponent.self] {
            sparks.mainEmitter.color = .constant(.single(color))
            trail.components.set(sparks)
        }
    }
}
