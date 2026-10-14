import RealityKit
import simd
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Il drago gira attorno a un'entità (la base del tronco dell'albero).
/// Il percorso è nello spazio dell'ancora; ogni frame il `DragonBodySystem` passa al ViewModel anche la
/// trasformazione dell'ancora nella scena: il drago prigioniero vola nello spazio dell'albero, quindi segue
/// l'isola se ruota, si sposta, scala o fluttua.
struct OrbitComponent: Component {
    let anchor: Entity
    /// Percorso nello spazio dell'ancora (metri dell'asset dell'isola).
    var path: OrbitPath

    @MainActor
    func anchoredOrbit() -> AnchoredOrbit {
        AnchoredOrbit(path: path, worldFromAnchor: anchor.transformMatrix(relativeTo: nil))
    }
}

/// Segna i collider del drago che si possono toccare (solo mentre è prigioniero sull'isola).
/// Il `SpatialTapGesture` punta a questo componente, non ai collider: così non compete con le prese
/// del minigioco (`ManipulationComponent`).
struct DragonTapTargetComponent: Component {}

/// Stato della storia già applicato alle entità del drago.
/// Il `DragonBodySystem` confronta la fase del ViewModel con quella applicata e riconfigura le entità
/// solo quando cambia (tocco ↔ presa ↔ nessuna interazione); ogni frame sfuma il drago.
struct DetanglingStateComponent: Component {
    /// `nil` = mai applicata (il primo frame configura tutto).
    var appliedPhase: DragonPhase?
    var dragonOpacity: Float = 0

    /// Tempo per far apparire il drago.
    static let fadeDuration: Float = 0.6
    /// Raggio dei collider da toccare: più grande del corpo, il drago si muove ed è lontano.
    static let tapRadius: Float = 0.09

    @MainActor
    mutating func apply(phase: DragonPhase, colliders: [Entity], config: TangleConfig) {
        guard phase != appliedPhase else { return }
        if appliedPhase?.interaction != phase.interaction {
            Self.configure(colliders, for: phase.interaction, config: config)
        }
        appliedPhase = phase
    }

    @MainActor
    mutating func fade(dragonOpacity newDragonOpacity: Float, dragon: Entity, deltaTime: Float) {
        // Svanire lo decide il ViewModel (andandosene); apparire è sempre una dissolvenza (niente comparse di colpo).
        let opacity = newDragonOpacity > dragonOpacity
            ? min(newDragonOpacity, dragonOpacity + deltaTime / Self.fadeDuration) : newDragonOpacity
        if opacity != dragonOpacity {
            dragonOpacity = opacity
            dragon.components.set(OpacityComponent(opacity: dragonOpacity))
        }
    }

    /// Prigioniero: tutto il corpo si tocca (sfere grandi, evidenziate se guardate).
    /// Minigioco: ogni nodo si afferra, tranne la testa ancorata. In volo: niente.
    @MainActor
    private static func configure(_ colliders: [Entity], for interaction: DragonPhase.Interaction, config: TangleConfig) {
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
                if config.anchorHead && index == 0 {
                    collider.components[InputTargetComponent.self]?.isEnabled = false
                } else {
                    DragonSceneBuilder.makeGrabbable(collider, radius: config.radius)
                }
            case .none:
                collider.components.remove(DragonTapTargetComponent.self)
                collider.components[InputTargetComponent.self]?.isEnabled = false
            }
        }
    }
}
