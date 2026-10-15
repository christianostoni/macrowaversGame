import RealityKit
import simd
import UIKit

// MARK: - Orbs

extension OrchardSystem {
    /// Moves every fruit's orb for its state: sealed in the fruit, rising out of it, in the player's hand, in the
    /// kalash (fusing into the spell when it is cast), spent.
    @MainActor
    static func updateOrbs(orchard: OrchardComponent, deltaTime: Float) {
        let viewModel = orchard.viewModel
        let pulse = 1 + 0.08 * sin(orchard.time * 4)
        let follow = 1 - exp(-deltaTime * 10)
        for fruit in orchard.fruits {
            let id = fruit.fruit.id
            guard let orb = orchard.orbs[id], viewModel.orbs.indices.contains(id) else { continue }
            let isFocused = id == viewModel.focusedFruitID
            switch viewModel.orbs[id] {
            case .sealed:
                showSealed(orb, in: fruit, isVisible: isFocused && fruit.showsSealedOrb)
            case .revealed:
                guard isFocused else {
                    orb.isEnabled = false
                    continue
                }
                showRevealed(orb, above: fruit, viewModel: viewModel, time: orchard.time, follow: follow)
                orb.setScale(SIMD3(repeating: pulse), relativeTo: nil)
            case .held:
                // The drag gesture moves it.
                orb.isEnabled = true
                orb.components[InputTargetComponent.self]?.isEnabled = true
                orb.setScale(SIMD3(repeating: pulse), relativeTo: nil)
            case .stored(let slot):
                showStored(orb, slot: slot, kalash: orchard.kalash, spell: viewModel.kalash, follow: follow)
            case .spent:
                orb.isEnabled = false
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

    /// Rises out of the opened fruit and floats above it; it can be grabbed once it is out. Let go away from
    /// the kalash, it glides back here.
    @MainActor
    private static func showRevealed(_ orb: Entity, above fruit: OrchardFruit, viewModel: OrchardViewModel,
                                     time: Float, follow: Float) {
        attach(orb, to: fruit.orbAnchor, preservingWorldTransform: true)
        orb.isEnabled = true
        let rise = min(viewModel.orbRevealTimes[fruit.fruit.id] / 1.2, 1)
        let eased = rise * rise * (3 - 2 * rise)
        let target = SIMD3<Float>(0, fruit.orbHeight(viewModel: viewModel) * eased + 0.01 * sin(time * 2), 0)
        orb.position = simd_mix(orb.position, target, SIMD3(repeating: follow))
        orb.components[InputTargetComponent.self]?.isEnabled = rise >= 1
    }

    /// In its slot above the kalash's mouth; while the spell forms it spirals up into it.
    @MainActor
    private static func showStored(_ orb: Entity, slot: Int, kalash: KalashRig, spell: Kalash, follow: Float) {
        attach(orb, to: kalash.root, preservingWorldTransform: true)
        orb.isEnabled = true
        orb.components[InputTargetComponent.self]?.isEnabled = false
        let target = kalash.storedOrbPosition(slot: slot, spell: spell)
        orb.position = spell.spell == .forming ? target : simd_mix(orb.position, target, SIMD3(repeating: follow))
        orb.setScale(SIMD3(repeating: kalash.storedOrbScale(spell: spell)), relativeTo: nil)
    }

    @MainActor
    static func attach(_ entity: Entity, to parent: Entity, preservingWorldTransform: Bool) {
        guard entity.parent !== parent else { return }
        entity.setParent(parent, preservingWorldTransform: preservingWorldTransform)
    }
}

// MARK: - Building

extension OrchardSceneBuilder {
    /// The orb found in every fruit: `Artifact.usdz` from the bundle when the design team delivers it, otherwise
    /// a glowing golden orb (placeholder). Origin at its centre, about 5 cm wide. Cloned for every fruit.
    @MainActor
    static func makeOrbTemplate() async -> Entity {
        let orb = Entity()
        if let asset = try? await Entity(named: "Artifact", in: .main) {
            orb.addChild(asset)
        } else {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: UIColor(red: 1, green: 0.8, blue: 0.35, alpha: 1))
            material.emissiveColor = .init(color: UIColor(red: 1, green: 0.75, blue: 0.3, alpha: 1))
            material.emissiveIntensity = 2.5
            material.metallic = 0.6
            material.roughness = 0.2
            orb.addChild(ModelEntity(mesh: .generateSphere(radius: 0.025), materials: [material]))
            var halo = UnlitMaterial(color: UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1))
            halo.blending = .transparent(opacity: .init(floatLiteral: 0.25))
            orb.addChild(ModelEntity(mesh: .generateSphere(radius: 0.038), materials: [halo]))
        }
        // Generous: it is pinched and carried to the kalash.
        orb.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.05)]))
        orb.components.set(InputTargetComponent.disabled)
        orb.components.set(HoverEffectComponent())
        return orb
    }
}

extension Entity {
    /// The orchard's root (the entity with the `OrchardComponent`) above this entity, if any.
    var orchardRoot: Entity? {
        var entity: Entity? = self
        while let current = entity {
            if current.components.has(OrchardComponent.self) { return current }
            entity = current.parent
        }
        return nil
    }
}
