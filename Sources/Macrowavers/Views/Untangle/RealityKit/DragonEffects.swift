import Foundation
import RealityKit
import simd
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Dragon effects shared by every rig: smoke from the nostrils, fire, sounds.
/// Sounds are optional: if the bundle contains `DragonGrowl`, `DragonRoar`, `DragonRumble`,
/// `DragonWhoosh` (m4a/wav/mp3/caf) they play as spatial audio from the head.
@MainActor
final class DragonEffects {
    nonisolated static let soundNames = ["DragonGrowl", "DragonRoar", "DragonRumble", "DragonWhoosh"]

    private let smoke = Entity()
    private let fire = Entity()
    private weak var voiceSource: Entity?
    private var sounds: [String: AudioFileResource] = [:]
    private var lastAction: DragonAction?
    private var lastMood: DragonMood?
    private var lastManeuver: DragonFlight.Maneuver?
    private var smokeLevel = -1
    private var fireLevel = -1

    init() {
        smoke.name = "NostrilSmoke"
        smoke.components.set(Self.smokeEmitter())
        fire.name = "FireBreath"
        fire.components.set(Self.fireEmitter())
    }

    /// `nostrils` and `mouth` are where smoke and fire come out (children of the head). `voice` is the head
    /// itself, snout towards +Z: the sounds come from it and the smoke and fire leave along its snout.
    func attach(nostrils: Entity, mouth: Entity, voice: Entity) {
        nostrils.addChild(smoke)
        mouth.addChild(fire)
        // The asset's markers inherit the export's Z-up → Y-up rotation: their own +Z points out of the top of
        // the head. The emitters face the snout instead, whatever the axes of the markers.
        let snout = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        smoke.setOrientation(snout, relativeTo: voice)
        fire.setOrientation(snout, relativeTo: voice)
        voiceSource = voice
        voice.components.set(SpatialAudioComponent(gain: -6))
        // In the background: read here, the files held up the frame that builds the dragon.
        Task { await loadSounds() }
    }

    func update(pose: DragonPose, frame: DragonFrame) {
        // Updates the emitters only when the intensity changes by a "step".
        let newSmoke = Int((pose.smoke * 10).rounded())
        if newSmoke != smokeLevel {
            smokeLevel = newSmoke
            smoke.components[ParticleEmitterComponent.self]?.mainEmitter.birthRate = Float(newSmoke) * 8
        }
        let newFire = Int((pose.fire * 10).rounded())
        if newFire != fireLevel {
            fireLevel = newFire
            fire.components[ParticleEmitterComponent.self]?.mainEmitter.birthRate = Float(newFire) * 60
        }

        playSounds(for: frame)
    }

    /// Sounds tied to changes of move, manoeuvre or mood.
    private func playSounds(for frame: DragonFrame) {
        if frame.action != lastAction {
            lastAction = frame.action
            if let name = Self.sound(for: frame.action) { play(name) }
        }
        let maneuver = frame.flight?.maneuver
        if maneuver != lastManeuver {
            lastManeuver = maneuver
            if let name = Self.sound(for: maneuver) { play(name) }
        }
        if frame.mood != lastMood {
            if frame.mood == .restless { play("DragonGrowl") }
            lastMood = frame.mood
        }
    }

    private static func sound(for action: DragonAction?) -> String? {
        switch action {
        case .rearUp: "DragonRoar"
        case .turn: "DragonRumble"
        case .tailLash, .coil: "DragonWhoosh"
        case nil: nil
        }
    }

    private static func sound(for maneuver: DragonFlight.Maneuver?) -> String? {
        switch maneuver {
        case .takeoff, .swoop, .approach: "DragonWhoosh"
        case .hover, .depart: "DragonRoar"
        default: nil
        }
    }

    private func play(_ name: String) {
        guard let sound = sounds[name], let voiceSource else { return }
        voiceSource.playAudio(sound)
    }

    /// A sound missing from the bundle stays silent.
    private func loadSounds() async {
        for name in Self.soundNames {
            if let sound = await GameAudio.load(name) { sounds[name] = sound }
        }
    }

    /// Grey puffs of smoke that rise and spread.
    private static func smokeEmitter() -> ParticleEmitterComponent {
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .point
        emitter.emissionDirection = SIMD3(0, 0.4, 1)
        emitter.speed = 0.05
        emitter.speedVariation = 0.02
        emitter.mainEmitter.birthRate = 0
        emitter.mainEmitter.lifeSpan = 1.4
        emitter.mainEmitter.size = 0.008
        emitter.mainEmitter.sizeMultiplierAtEndOfLifespan = 5
        emitter.mainEmitter.spreadingAngle = 0.4
        emitter.mainEmitter.acceleration = SIMD3(0, 0.04, 0)
        emitter.mainEmitter.dampingFactor = 1.5
        emitter.mainEmitter.opacityCurve = .linearFadeOut
        emitter.mainEmitter.color = .evolving(start: .single(.init(white: 0.75, alpha: 0.5)),
                                              end: .single(.init(white: 0.35, alpha: 0)))
        return emitter
    }

    /// Short burst of fire, yellow → red.
    private static func fireEmitter() -> ParticleEmitterComponent {
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .point
        // `.local`: along `emissionDirection` (the snout). The default, `.normal`, ignores it and fires upwards.
        emitter.birthDirection = .local
        emitter.emissionDirection = SIMD3(0, 0, 1)
        // The flames move with the head while it roars, so they keep coming out of the mouth.
        emitter.particlesInheritTransform = true
        emitter.speed = 0.6
        emitter.speedVariation = 0.15
        emitter.mainEmitter.birthRate = 0
        emitter.mainEmitter.lifeSpan = 0.35
        emitter.mainEmitter.size = 0.012
        emitter.mainEmitter.sizeMultiplierAtEndOfLifespan = 3
        emitter.mainEmitter.spreadingAngle = 0.25
        emitter.mainEmitter.opacityCurve = .quickFadeInOut
        emitter.mainEmitter.color = .evolving(start: .single(.init(red: 1, green: 0.85, blue: 0.3, alpha: 1)),
                                              end: .single(.init(red: 0.9, green: 0.15, blue: 0.05, alpha: 0)))
        return emitter
    }
}

/// Wings of the placeholder dragon: one membrane per side attached to the "shoulders".
/// Folded along the body, they spread when the dragon rears up or is free.
@MainActor
final class ProceduralWings {
    let entity = Entity()
    private var pivots: [(side: Float, pivot: Entity)] = []
    /// Body node the wings are attached to.
    let shoulderIndex: Int

    init(radius: Float, shoulderIndex: Int) {
        self.shoulderIndex = shoulderIndex
        entity.name = "Wings"
        var membrane = PhysicallyBasedMaterial()
        membrane.baseColor = .init(tint: PlatformColor(red: 0.35, green: 0.25, blue: 0.2, alpha: 1))
        membrane.blending = .transparent(opacity: .init(floatLiteral: 0.85))
        let boneMaterial = SimpleMaterial(color: PlatformColor(red: 0.15, green: 0.35, blue: 0.22, alpha: 1),
                                          roughness: 0.6, isMetallic: false)

        for side: Float in [-1, 1] {
            let pivot = Entity()
            let wingSpan = radius * 5
            let skin = ModelEntity(mesh: .generateBox(width: wingSpan, height: 0.002, depth: radius * 3,
                                                      cornerRadius: 0.001),
                                   materials: [membrane])
            skin.position = SIMD3(side * wingSpan / 2, 0, -radius * 0.8)
            // Front bone of the wing.
            let bone = ModelEntity(mesh: .generateBox(width: wingSpan, height: radius * 0.25, depth: radius * 0.25,
                                                      cornerRadius: radius * 0.1),
                                   materials: [boneMaterial])
            bone.position = SIMD3(side * wingSpan / 2, 0, radius * 0.6)
            pivot.addChild(skin)
            pivot.addChild(bone)
            entity.addChild(pivot)
            pivots.append((side, pivot))
        }
    }

    /// `position` and `forward` of the shoulder (dragon space). In flight `forward` is tilted: the wings follow.
    func update(position: SIMD3<Float>, forward: SIMD3<Float>, pose: DragonPose, radius: Float) {
        let body = simd_length(forward) > 1e-5
            ? DragonLifeAnimator.orientation(looking: simd_normalize(forward))
            : simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        entity.position = position + SIMD3(0, radius * 0.9, 0)
        entity.orientation = body

        let flare = pose.wingFlare
        // Folded: bent backwards and lying down. Spread: open and raised.
        let sweep = 1.2 - 0.9 * flare
        let lift = -0.15 + 1.0 * flare + pose.wingFlap
        for (side, pivot) in pivots {
            pivot.orientation = simd_quatf(angle: side * sweep, axis: SIMD3(0, 1, 0))
                * simd_quatf(angle: side * lift, axis: SIMD3(0, 0, 1))
        }
    }
}
