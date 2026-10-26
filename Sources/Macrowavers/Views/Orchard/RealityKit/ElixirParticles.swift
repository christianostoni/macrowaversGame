import RealityKit
import simd
import UIKit

/// The elixir's particles: the flash of the brewed elixir, the bubbles in the flask, and the pour (the stream from
/// the neck, the splash on the dragon's head, the shimmer of the soothed dragon). Built and driven by `ElixirRig`.
extension ElixirRig {
    /// Sets how many particles per second an emitter gives (0 = none) and, for the stream, its direction: only when
    /// they change enough (it is called every frame; setting the component rebuilds the emitter).
    static func emit(_ entity: Entity, rate: Float, direction: SIMD3<Float>?) {
        guard var emitter = entity.components[ParticleEmitterComponent.self] else { return }
        let isEmitting = rate > 0.5
        var changed = emitter.isEmitting != isEmitting
            || abs(emitter.mainEmitter.birthRate - rate) > max(2, 0.1 * emitter.mainEmitter.birthRate)
        if let direction, simd_distance(emitter.emissionDirection, direction) > 0.05 {
            emitter.emissionDirection = direction
            changed = true
        }
        guard changed else { return }
        emitter.isEmitting = isEmitting
        emitter.mainEmitter.birthRate = rate
        entity.components.set(emitter)
    }

    static func burst(_ entity: Entity) {
        guard var emitter = entity.components[ParticleEmitterComponent.self] else { return }
        emitter.burst()
        entity.components.set(emitter)
    }

    static func makeBurst() -> Entity {
        let entity = Entity()
        var burst = ParticleEmitterComponent()
        burst.emitterShape = .sphere
        burst.emitterShapeSize = SIMD3(repeating: 0.06)
        burst.birthDirection = .normal
        burst.speed = 0.35
        burst.speedVariation = 0.15
        burst.isEmitting = false
        burst.burstCount = 160
        burst.mainEmitter.lifeSpan = 0.9
        burst.mainEmitter.size = 0.004
        burst.mainEmitter.color = .evolving(start: .single(UIColor(red: 0.85, green: 0.95, blue: 1, alpha: 1)),
                                            end: .single(OrchardSceneBuilder.color(Elixir.elixirColor)))
        entity.components.set(burst)
        return entity
    }

    /// Bubbles rising from the bottom of the round body (flask space: its origin is the body's centre).
    static func makeBubbles() -> Entity {
        let entity = Entity()
        entity.position = SIMD3(0, -0.05, 0)
        var bubbles = ParticleEmitterComponent()
        bubbles.emitterShape = .sphere
        bubbles.emitterShapeSize = SIMD3(0.05, 0.02, 0.05)
        bubbles.birthDirection = .local
        bubbles.emissionDirection = SIMD3(0, 1, 0)
        bubbles.speed = 0.04
        bubbles.speedVariation = 0.015
        bubbles.burstCount = 40
        bubbles.mainEmitter.birthRate = 0
        bubbles.mainEmitter.lifeSpan = 1.1
        bubbles.mainEmitter.size = 0.004
        bubbles.mainEmitter.color = .constant(.single(UIColor(white: 1, alpha: 0.7)))
        entity.components.set(bubbles)
        return entity
    }

    /// The elixir pouring out of the neck's mouth (its direction follows the neck) and falling onto the head: a
    /// thick, glowing stream that lives just long enough to reach it (`Elixir.Pour.fall`).
    static func makeStream() -> Entity {
        let entity = Entity()
        var stream = ParticleEmitterComponent()
        stream.emitterShape = .sphere
        stream.emitterShapeSize = SIMD3(repeating: 0.007)
        stream.birthDirection = .local
        stream.emissionDirection = SIMD3(0, -1, 0)
        stream.speed = 0.15
        stream.speedVariation = 0.04
        stream.isEmitting = false
        stream.mainEmitter.birthRate = 0
        stream.mainEmitter.lifeSpan = 0.32
        stream.mainEmitter.size = 0.006
        stream.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.6
        stream.mainEmitter.spreadingAngle = 0.08
        stream.mainEmitter.acceleration = SIMD3(0, -2.2, 0)
        stream.mainEmitter.blendMode = .additive
        stream.mainEmitter.color = .evolving(start: .single(OrchardSceneBuilder.color(Elixir.elixirColor)),
                                             end: .single(UIColor(red: 0.7, green: 0.88, blue: 1, alpha: 1)))
        entity.components.set(stream)
        return entity
    }

    /// Droplets bouncing off the top of the dragon's head where the stream lands, falling back around it.
    static func makeSplash() -> Entity {
        let entity = Entity()
        var splash = ParticleEmitterComponent()
        splash.emitterShape = .sphere
        splash.emitterShapeSize = SIMD3(0.05, 0.02, 0.05)
        splash.birthDirection = .normal
        splash.speed = 0.18
        splash.speedVariation = 0.08
        splash.isEmitting = false
        splash.mainEmitter.birthRate = 0
        splash.mainEmitter.lifeSpan = 0.55
        splash.mainEmitter.size = 0.004
        splash.mainEmitter.acceleration = SIMD3(0, -1.6, 0)
        splash.mainEmitter.opacityCurve = .linearFadeOut
        splash.mainEmitter.color = .evolving(start: .single(OrchardSceneBuilder.color(Elixir.elixirColor)),
                                             end: .single(UIColor(red: 0.85, green: 0.95, blue: 1, alpha: 1)))
        entity.components.set(splash)
        return entity
    }

    /// Once the dragon is soothed: sparkles rising all around its head and fading slowly.
    static func makeShimmer() -> Entity {
        let entity = Entity()
        var shimmer = ParticleEmitterComponent()
        shimmer.emitterShape = .sphere
        shimmer.emitterShapeSize = SIMD3(repeating: 0.14)
        shimmer.birthDirection = .normal
        shimmer.speed = 0.12
        shimmer.speedVariation = 0.06
        shimmer.isEmitting = false
        shimmer.burstCount = 260
        shimmer.mainEmitter.lifeSpan = 1.3
        shimmer.mainEmitter.size = 0.005
        shimmer.mainEmitter.acceleration = SIMD3(0, 0.12, 0)
        shimmer.mainEmitter.opacityCurve = .quickFadeInOut
        shimmer.mainEmitter.blendMode = .additive
        shimmer.mainEmitter.color = .evolving(start: .single(UIColor(red: 0.85, green: 0.95, blue: 1, alpha: 1)),
                                              end: .single(OrchardSceneBuilder.color(Elixir.elixirColor)))
        entity.components.set(shimmer)
        return entity
    }
}
