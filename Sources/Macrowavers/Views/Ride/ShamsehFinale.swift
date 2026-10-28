import RealityKit
import simd
import UIKit

/// Chapter II's end: the medallion every fruit eaten colours (`Shamseh`, drawn by `ShamsehSky`), and the finale, the
/// dragon flying into its heart through a rush of light; once through it, the ride ends and the story's last pages
/// show back in the room (`ContentView`).
extension DragonRideSystem {
    /// The medallion shows through the feast and the finale.
    static func showsShamseh(_ step: StoryStep) -> Bool {
        step == .feast || step == .finale
    }

    /// The finale: once the full medallion has swelled, the dragon roars and turns to it on its own, then flies
    /// into its heart as light rushes past; once through it, the ride is over (the room comes back).
    @MainActor
    static func flyIntoShamseh(_ state: inout DragonRideComponent, deltaTime: Float) {
        if state.story.step == .feast, state.shamsehSky.isCelebrated {
            state.story.feastCelebrated()
        }
        let step = state.story.step
        guard step == .finale, let direction = state.shamsehSky.direction else { return }
        if state.finaleTime == nil { play(.roar, from: state.mouth, sounds: state.sounds) }
        let time = (state.finaleTime ?? 0) + deltaTime
        state.finaleTime = time
        state.ride.destination = direction
        // Off into it once facing it (or after a while anyway).
        if state.approachTime == nil, simd_dot(state.ride.forward, direction) > 0.995 || time > finaleTurn {
            state.approachTime = 0
        }
        guard let approachTime = state.approachTime else { return }
        let elapsed = approachTime + deltaTime
        state.approachTime = elapsed
        let flight = min(elapsed / finaleFlight, 1)
        state.shamsehSky.approach = flight
        let rush = 900 * Elixir.smoothstep(from: 0, to: 0.4, flight)
        state.rush.components[ParticleEmitterComponent.self]?.mainEmitter.birthRate = rush
        if elapsed > finaleFlight {
            state.story.rideEnded()
        }
    }
}

// MARK: - Building

extension DragonRideSceneBuilder {
    /// The medallion's drawing, hung in the sky.
    @MainActor
    static func addShamseh(_ shamseh: Shamseh, root: Entity, airbrush: RideAirbrush?) -> ShamsehSky {
        let sky = ShamsehSky(shamseh, airbrush: airbrush)
        root.addChild(sky.pivot)
        return sky
    }

    /// The finale's rush of light.
    @MainActor
    static func addFinaleRush(root: Entity) -> Entity {
        let rush = makeRush()
        root.addChild(rush)
        return rush
    }

    /// The finale's rush of light: specks born far ahead that stream past the player, in the flowers' gold and
    /// lilac (silent until the dragon flies into the medallion).
    @MainActor
    private static func makeRush() -> Entity {
        let rush = Entity()
        rush.name = "RideRush"
        rush.position = SIMD3(0, 0, -30)
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .box
        emitter.emitterShapeSize = SIMD3(26, 18, 4)
        emitter.birthLocation = .volume
        emitter.emissionDirection = SIMD3(0, 0, 1)
        emitter.speed = 22
        emitter.speedVariation = 6
        emitter.mainEmitter.birthRate = 0
        emitter.mainEmitter.lifeSpan = 1.6
        emitter.mainEmitter.size = 0.05
        emitter.mainEmitter.sizeVariation = 0.03
        emitter.mainEmitter.spreadingAngle = 0.05
        emitter.mainEmitter.opacityCurve = .quickFadeInOut
        emitter.mainEmitter.blendMode = .additive
        emitter.mainEmitter.isLightingEnabled = false
        emitter.mainEmitter.color = .evolving(start: .single(RidePalette.uiColor(RidePalette.paleGold)),
                                              end: .single(RidePalette.uiColor(RidePalette.lilac)))
        rush.components.set(emitter)
        return rush
    }

}
