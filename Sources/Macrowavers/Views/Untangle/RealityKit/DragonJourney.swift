import RealityKit
import simd
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The dragon circles an entity (the base of the tree's trunk).
/// The path is in the anchor's space; every frame the `DragonBodySystem` also passes the anchor's
/// transform in the scene to the view model: the captive dragon flies in the tree's space, so it follows
/// the island when it turns, moves, scales or bobs.
struct OrbitComponent: Component {
    let anchor: Entity
    /// Path in the anchor's space (island asset metres).
    var path: OrbitPath

    @MainActor
    func anchoredOrbit() -> AnchoredOrbit {
        AnchoredOrbit(path: path, worldFromAnchor: anchor.transformMatrix(relativeTo: nil))
    }
}

/// Marks the dragon's colliders that can be tapped (only while it is captive on the island).
/// The `SpatialTapGesture` targets this component, not the colliders: so it does not compete with the
/// mini-game's grabs (`ManipulationComponent`).
struct DragonTapTargetComponent: Component {}

/// Story state already applied to the dragon's entities.
/// The `DragonBodySystem` compares the view model's chapter with the applied one and reconfigures the
/// entities only when it changes (tap ↔ grab ↔ no input); every frame it fades the dragon.
struct DetanglingStateComponent: Component {
    /// `nil` = never applied (the first frame configures everything).
    var appliedPhase: DragonPhase?
    var dragonOpacity: Float = 0

    /// Time for the dragon to appear.
    static let fadeDuration: Float = 0.6
    /// Radius of the tappable colliders: larger than the body, the dragon moves and is far away.
    static let tapRadius: Float = 0.09

    /// `grabTargets`: the rig's grabbable nodes and their sphere's radius (nil: every node).
    @MainActor
    mutating func apply(phase: DragonPhase, colliders: [Entity], config: TangleConfig, grabTargets: [Int: Float]?) {
        guard phase != appliedPhase else { return }
        if appliedPhase?.interaction != phase.interaction {
            Self.configure(colliders, for: phase.interaction, config: config, grabTargets: grabTargets)
        }
        appliedPhase = phase
    }

    @MainActor
    mutating func fade(dragonOpacity newDragonOpacity: Float, dragon: Entity, deltaTime: Float) {
        // Fading out is decided by the view model (as it leaves); appearing is always a fade (no sudden pop).
        let opacity = newDragonOpacity > dragonOpacity
            ? min(newDragonOpacity, dragonOpacity + deltaTime / Self.fadeDuration) : newDragonOpacity
        if opacity != dragonOpacity {
            dragonOpacity = opacity
            // Fully visible: no opacity at all, so the dragon is drawn in the opaque pass (as `FocusDimmingSystem`).
            if opacity >= 1 {
                dragon.components.remove(OpacityComponent.self)
            } else {
                dragon.components.set(OpacityComponent(opacity: dragonOpacity))
            }
        }
    }

    /// Captive: the whole body can be tapped (large spheres, highlighted when looked at).
    /// Mini-game: every node can be grabbed, head included, or only the rig's grab targets (the stone dragon: the
    /// head and one node per stone). Flying: nothing.
    @MainActor
    private static func configure(_ colliders: [Entity], for interaction: DragonPhase.Interaction, config: TangleConfig,
                                  grabTargets: [Int: Float]?) {
        for (index, collider) in colliders.enumerated() {
            switch interaction {
            case .tap:
                #if os(visionOS)
                collider.components.remove(ManipulationComponent.self)
                #endif
                collider.components.set(DragonTapTargetComponent())
                collider.components.set(CollisionComponent(shapes: [.generateSphere(radius: tapRadius)]))
                collider.components.set(InputTargetComponent())
                collider.components.set(HoverEffectComponent(.highlight(.init(color: DragonSceneBuilder.hoverColor,
                                                                               strength: 0.8))))
            case .grab:
                collider.components.remove(DragonTapTargetComponent.self)
                let isTarget = grabTargets.map { $0[index] != nil } ?? true
                if !isTarget {
                    // A node with no stone cannot be grabbed: no shape at all, or its large tap sphere would sit over
                    // the body and catch the pinches meant for the grabbable nodes.
                    #if os(visionOS)
                    collider.components.remove(ManipulationComponent.self)
                    #endif
                    collider.components.remove(HoverEffectComponent.self)
                    collider.components[InputTargetComponent.self]?.isEnabled = false
                    collider.components.remove(CollisionComponent.self)
                } else {
                    DragonSceneBuilder.makeGrabbable(collider, config: config, radius: grabTargets?[index])
                }
            case .none:
                collider.components.remove(DragonTapTargetComponent.self)
                collider.components[InputTargetComponent.self]?.isEnabled = false
                collider.components.remove(CollisionComponent.self)
            }
        }
    }
}
