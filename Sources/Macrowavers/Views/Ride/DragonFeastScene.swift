import Foundation
import RealityKit
import simd
import UIKit

/// A fruit drawn in the sky: its entity and the look it shows (re-cloned when the plant changes kind or poison).
struct DrawnFruit {
    let entity: Entity
    let kind: FruitKind
    let isPoisoned: Bool
    /// It was already burning last frame (its embers have flown).
    var isBurning = false
}

/// Chapter II drawn (`DragonFeast` decides): the snap that breathes fire, read without letting it steer the dragon,
/// the fruit (poisoned ones dark in a sickly haze), the long breath of fire from the middle of the dragon's mouth,
/// the embers of a burnt fruit, the medallion's petals (`Shamseh`) and the sounds.
extension DragonRideSystem {
    /// The hands that snapped this frame: only while the player feeds the dragon (the detector rests otherwise).
    @MainActor
    static func readSnap(_ state: inout DragonRideComponent) -> Set<HandSample.Chirality> {
        guard state.story.step == .feast, state.feast != nil else {
            state.snap.reset()
            return []
        }
        state.snap.beginFrame()
        var snapped: Set<HandSample.Chirality> = []
        // Both hands every frame (no early exit): each keeps its own state.
        for (chirality, sample) in state.hands.samples where state.snap.process(sample) {
            snapped.insert(chirality)
        }
        return snapped
    }

    /// The hands on the horns (ride space): each one where it pinches (between thumb and index), only while it
    /// pinches.
    @MainActor
    static func pinchedHands(_ state: inout DragonRideComponent,
                             root: Entity) -> (left: SIMD3<Float>?, right: SIMD3<Float>?) {
        var grips: [HandSample.Chirality: SIMD3<Float>] = [:]
        for chirality in HandSample.Chirality.allCases {
            var pinch = state.pinches[chirality] ?? Pinch()
            if let sample = state.hands.samples[chirality] {
                pinch.update(thumbTip: sample.thumbTip, indexTip: sample.indexTip)
                if pinch.isPinching {
                    grips[chirality] = root.convert(position: (sample.thumbTip + sample.indexTip) / 2, from: nil)
                }
            } else {
                pinch.release()
            }
            state.pinches[chirality] = pinch
        }
        return (grips[.left], grips[.right])
    }

    /// The hands holding the horns (ride space, `pinchedHands`), a hand making the snap held where it was
    /// (`SteeringHold`): one still pinching while its thumb loads the snap never swerves the dragon.
    @MainActor
    static func steeringHands(_ state: inout DragonRideComponent, root: Entity,
                              snapped: Set<HandSample.Chirality>) -> (left: SIMD3<Float>?, right: SIMD3<Float>?) {
        let (left, right) = pinchedHands(&state, root: root)
        let loaded = Set([HandSample.Chirality.left, .right].filter { state.snap.isLoaded($0) })
        return state.steeringHold.steering(left: left, right: right, loaded: loaded, snapped: snapped,
                                           time: state.ride.time)
    }

    /// A snap: the dragon breathes fire, if its fire is ready.
    @MainActor
    static func breatheFire(_ state: inout DragonRideComponent) {
        guard var feast = state.feast, feast.breatheFire() else { return }
        state.feast = feast
        play(.roar, from: state.mouth, sounds: state.sounds)
    }

    /// The fruit: eaten, spat out, poisoning the dragon, burnt; the tally; the medallion's petals (one per fruit
    /// eaten; out of hearts, the petals of the fruit the dragon lost fade).
    @MainActor
    static func feed(_ state: inout DragonRideComponent, mouth: SIMD3<Float>, deltaTime: Float) {
        guard var feast = state.feast else { return }
        let events = feast.update(deltaTime: deltaTime, mouth: state.ride.skyFromRide(mouth), ride: state.ride,
                                  using: &state.random)
        state.feast = feast
        state.story.showFeast(feast.progress)
        for event in events {
            switch event {
            case .ate(let fruit):
                state.shamseh.colour(with: fruit)
                play(.eating(fruit), from: state.mouth, sounds: state.sounds)
            case .refused: play(.growl, from: state.mouth, sounds: state.sounds)
            case .poisoned: play(.squish, from: state.mouth, sounds: state.sounds)
            case .burned: break
            case .stageReached: play(.chime, from: state.mouth, sounds: state.sounds)
            case .exhausted(let lost):
                state.shamseh.uncolour(last: lost)
                play(.rumble, from: state.mouth, sounds: state.sounds)
            case .finished: play(.chime, from: state.mouth, sounds: state.sounds)
            }
        }
        draw(feast, in: &state)
    }

    @MainActor
    private static func draw(_ feast: DragonFeast, in state: inout DragonRideComponent) {
        for plant in feast.plants {
            var drawn = state.fruit[plant.id]
            if drawn?.kind != plant.kind || drawn?.isPoisoned != plant.isPoisoned {
                drawn?.entity.removeFromParent()
                let models = plant.isPoisoned ? state.poisonedModels : state.fruitModels
                guard let model = models[plant.kind]?.clone(recursive: true) else { continue }
                state.sky.addChild(model)
                drawn = DrawnFruit(entity: model, kind: plant.kind, isPoisoned: plant.isPoisoned)
            }
            guard var fruit = drawn else { continue }
            let entity = fruit.entity
            entity.position = plant.position
            entity.orientation = simd_quatf(angle: plant.spin, axis: simd_normalize(SIMD3(0.3, 1, 0.2)))
            let (size, opacity) = look(of: plant.state)
            var isBurning = false
            if case .burnt = plant.state { isBurning = true }
            if isBurning && !fruit.isBurning { burstEmbers(at: plant.position, in: &state) }
            fruit.isBurning = isBurning
            entity.isEnabled = opacity > 0.001
            entity.scale = SIMD3(repeating: size)
            if opacity >= 1 {
                entity.components.remove(OpacityComponent.self)
            } else {
                entity.components.set(OpacityComponent(opacity: opacity))
            }
            state.fruit[plant.id] = fruit
        }
    }

    /// A fruit's size and opacity: swallowed (shrinking), spat out or fading (fading), burnt (both).
    private static func look(of state: DragonFeast.PlantState) -> (size: Float, opacity: Float) {
        switch state {
        case .floating: (fruitSize, 1)
        case .eaten(let progress): (fruitSize * (1 - progress), 1)
        case .spat(let progress, _): (fruitSize, 1 - Elixir.smoothstep(from: 0.5, to: 1, progress))
        case .burnt(let progress): (fruitSize * (1 - 0.6 * progress), 1 - progress)
        case .fading(let progress): (fruitSize, 1 - progress)
        }
    }

    /// Embers fly where a fruit catches fire (the puffs are used in turn).
    @MainActor
    private static func burstEmbers(at position: SIMD3<Float>, in state: inout DragonRideComponent) {
        guard !state.embers.isEmpty else { return }
        let ember = state.embers[state.nextEmber % state.embers.count]
        state.nextEmber += 1
        ember.position = position
        ElixirRig.burst(ember)
    }

    /// The long breath of fire, from the middle of the dragon's mouth along its snout (the rig moves the mouth with
    /// the jaw), as strong as the breath.
    @MainActor
    static func drawFire(_ state: DragonRideComponent, root: Entity) {
        guard let mouth = state.rig.mouth else { return }
        state.fireBreath.position = root.convert(position: .zero, from: mouth)
        let direction = root.convert(direction: SIMD3(0, 0, 1), from: mouth)
        if simd_length(direction) > 1e-4 {
            state.fireBreath.orientation = simd_quatf(from: SIMD3(0, 0, 1), to: simd_normalize(direction))
        }
        ElixirRig.emit(state.fireBreath, rate: DragonEffects.fireRate * (state.feast?.fire ?? 0),
                       direction: nil)
    }

    @MainActor
    static func play(_ sound: Sound, from entity: Entity, sounds: [Sound: AudioFileResource]) {
        guard let resource = sounds[sound] else { return }
        entity.playAudio(resource)
    }
}

// MARK: - Building

extension DragonRideSceneBuilder {
    /// A poisoned fruit's colour (it tints the fruit's own) and its haze.
    static let poisonTint = UIColor(red: 0.42, green: 0.22, blue: 0.5, alpha: 1)
    static let poisonGlow = UIColor(red: 0.35, green: 0.85, blue: 0.25, alpha: 1)

    /// The breath of fire at the dragon's mouth (ride space) and the puffs of embers where fruit burn (sky space).
    @MainActor
    static func addFire(root: Entity, sky: Entity) -> (breath: Entity, embers: [Entity]) {
        let breath = makeFireBreath()
        root.addChild(breath)
        let embers = (0..<4).map { _ in makeEmbers() }
        embers.forEach { sky.addChild($0) }
        return (breath, embers)
    }

    /// The long breath of fire: the dragon's fire (`DragonEffects.fireEmitter`, its roar's on the island), fast
    /// enough to reach the fruit ~10 m ahead.
    @MainActor
    static func makeFireBreath() -> Entity {
        let entity = Entity()
        entity.name = "RideFireBreath"
        var emitter = DragonEffects.fireEmitter(size: 0.12, speed: 15, followsMouth: false)
        emitter.isEmitting = false
        entity.components.set(emitter)
        return entity
    }

    /// A puff of embers and soot where a fruit burns.
    @MainActor
    static func makeEmbers() -> Entity {
        let entity = Entity()
        var embers = ParticleEmitterComponent()
        embers.emitterShape = .sphere
        embers.emitterShapeSize = SIMD3(repeating: 0.35)
        embers.birthDirection = .normal
        embers.speed = 2
        embers.speedVariation = 1
        embers.isEmitting = false
        embers.burstCount = 80
        embers.mainEmitter.lifeSpan = 0.9
        embers.mainEmitter.size = 0.05
        embers.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.3
        embers.mainEmitter.acceleration = SIMD3(0, -1.5, 0)
        embers.mainEmitter.blendMode = .additive
        embers.mainEmitter.color = .evolving(start: .single(UIColor(red: 1, green: 0.75, blue: 0.3, alpha: 1)),
                                             end: .single(UIColor(red: 0.3, green: 0.1, blue: 0.05, alpha: 0)))
        entity.components.set(embers)
        return entity
    }

    /// The fruit the dragon likes, poisoned: their own models darkened to a sickly purple, glowing faintly green, in a
    /// green haze that clings to them. Bananas are never poisoned.
    @MainActor
    static func poisoned(_ models: [FruitKind: Entity]) -> [FruitKind: Entity] {
        var result: [FruitKind: Entity] = [:]
        for (kind, model) in models where kind.isLikedByDragon {
            let copy = model.clone(recursive: true)
            poison(copy)
            copy.addChild(makeHaze())
            result[kind] = copy
        }
        return result
    }

    /// Tints every material under `entity`: the fruit's own colours and textures, darkened (a material that cannot
    /// be tinted becomes plain poison purple).
    @MainActor
    private static func poison(_ entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            model.materials = model.materials.map { material -> any RealityKit.Material in
                if var physical = material as? PhysicallyBasedMaterial {
                    physical.baseColor.tint = poisonTint
                    physical.emissiveColor = .init(color: poisonGlow)
                    physical.emissiveIntensity = 0.35
                    return physical
                }
                if var simple = material as? SimpleMaterial {
                    simple.color.tint = poisonTint
                    return simple
                }
                var plain = PhysicallyBasedMaterial()
                plain.baseColor = .init(tint: poisonTint)
                plain.emissiveColor = .init(color: poisonGlow)
                plain.emissiveIntensity = 0.35
                plain.roughness = 0.6
                return plain
            }
            entity.components.set(model)
        }
        entity.children.forEach { poison($0) }
    }

    /// The sickly haze around a poisoned fruit (the fruit's model is one metre tall here): it moves with the fruit.
    @MainActor
    private static func makeHaze() -> Entity {
        let entity = Entity()
        entity.name = "PoisonHaze"
        var haze = ParticleEmitterComponent()
        haze.emitterShape = .sphere
        haze.emitterShapeSize = SIMD3(repeating: 0.45)
        haze.birthDirection = .normal
        haze.speed = 0.08
        haze.particlesInheritTransform = true
        haze.mainEmitter.birthRate = 30
        haze.mainEmitter.lifeSpan = 1.4
        haze.mainEmitter.size = 0.07
        haze.mainEmitter.sizeMultiplierAtEndOfLifespan = 3
        haze.mainEmitter.acceleration = SIMD3(0, 0.15, 0)
        haze.mainEmitter.opacityCurve = .gradualFadeInOut
        haze.mainEmitter.color = .evolving(start: .single(UIColor(red: 0.45, green: 0.9, blue: 0.3, alpha: 0.6)),
                                           end: .single(UIColor(red: 0.4, green: 0.15, blue: 0.5, alpha: 0)))
        entity.components.set(haze)
        return entity
    }
}
