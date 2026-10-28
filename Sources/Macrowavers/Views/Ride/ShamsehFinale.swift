import RealityKit
import simd
import UIKit

/// Chapter II's end: the medallion every fruit eaten colours (`Shamseh`, drawn by `ShamsehSky`), and the finale, the
/// dragon flying into its heart through a rush of light, where the story's last page shows.
extension DragonRideSystem {
    /// The medallion shows from the feast to the story's last page.
    static func showsShamseh(_ step: StoryStep) -> Bool {
        step == .feast || step == .finale || step == .epilogue
    }

    /// The finale: once the full medallion has swelled, the dragon roars and turns to it on its own, then flies
    /// into its heart as light rushes past; the light fills the view, and the story's last page shows in it (the
    /// light widens past the page, the rush calms down).
    @MainActor
    static func flyIntoShamseh(_ state: inout DragonRideComponent, deltaTime: Float) {
        if state.story.step == .feast, state.shamsehSky.isCelebrated {
            state.story.feastCelebrated()
        }
        let step = state.story.step
        guard step == .finale || step == .epilogue, let direction = state.shamsehSky.direction else { return }
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
        let rush = step == .epilogue ? 0 : 900 * Elixir.smoothstep(from: 0, to: 0.4, flight)
        state.rush.components[ParticleEmitterComponent.self]?.mainEmitter.birthRate = rush
        state.flash.isEnabled = flight > 0.75
        state.flash.components.set(OpacityComponent(opacity: Elixir.smoothstep(from: 0.8, to: 1, flight)))
        state.flash.scale = SIMD3(repeating: step == .epilogue ? epilogueLight : 1)
        if elapsed > finaleFlight + finaleHold {
            state.story.rideEnded()
        }
    }
}

// MARK: - Building

extension DragonRideSceneBuilder {
    /// The medallion's drawing, hung in the sky.
    @MainActor
    static func addShamseh(_ shamseh: Shamseh, root: Entity, airbrush: RideAirbrush?,
                           glass: ShaderGraphMaterial?) -> ShamsehSky {
        let sky = ShamsehSky(shamseh, airbrush: airbrush, glass: glass)
        root.addChild(sky.pivot)
        return sky
    }

    /// The finale's rush of light and the light at the medallion's heart.
    @MainActor
    static func addFinaleLight(root: Entity) -> (rush: Entity, flash: Entity) {
        let rush = makeRush()
        root.addChild(rush)
        let flash = makeFlash()
        root.addChild(flash)
        return (rush, flash)
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

    /// The light at the medallion's heart: it fills the view, all around the player, at the very end.
    @MainActor
    private static func makeFlash() -> Entity {
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: RidePalette.uiColor(simd_mix(RidePalette.paleGold, SIMD3(repeating: 1),
                                                                  SIMD3(repeating: 0.6))))
        material.faceCulling = .front
        let flash = ModelEntity(mesh: .generateSphere(radius: 0.4), materials: [material])
        flash.name = "RideFlash"
        flash.isEnabled = false
        flash.components.set(OpacityComponent(opacity: 0))
        return flash
    }
}
