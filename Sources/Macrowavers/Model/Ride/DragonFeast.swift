import Foundation
import simd

/// Chapter II on the dragon's back: fruit float among the clouds and the player steers the dragon into them to feed
/// it, wave after wave. It eats the fruit it likes and spits out the bananas (it doesn't like them: a waste of
/// time); a poisoned fruit makes it sick and costs one of its hearts. A snap of the fingers makes it breathe fire,
/// burning the fruit in front of it: the way to clear poisoned ones off the way (a good one burnt is lost).
/// Out of hearts, the dragon is exhausted: it rests, then the wave starts over. The last wave eaten, it is full.
/// Pure state, no RealityKit, like `DragonRide`: positions are in its sky space; `DragonRideSystem` draws them.
struct DragonFeast {
    enum PlantState: Equatable {
        case floating
        /// In the dragon's mouth, swallowed as `progress` goes 0...1.
        case eaten(progress: Float)
        /// Spat out: flung away (velocity in sky space, m/s), fading as `progress` goes 0...1.
        case spat(progress: Float, velocity: SIMD3<Float>)
        /// Caught in the dragon's fire: burning away as `progress` goes 0...1.
        case burnt(progress: Float)
        /// Leaving the sky between two waves (or at the end): fading as `progress` goes 0...1, then hidden.
        case fading(progress: Float)
    }

    /// A fruit floating in the sky.
    struct Plant: Identifiable, Equatable {
        let id: Int
        var kind: FruitKind
        /// A fruit the dragon likes, poisoned: dark, in a sickly haze. Bananas are never poisoned.
        var isPoisoned = false
        /// Sky space (m).
        var position: SIMD3<Float>
        var state = PlantState.floating
        /// Its slow tumble (radians), random so the fruit don't turn in step.
        var spin: Float

        var isFloating: Bool { state == .floating }
        /// The dragon wants it: a liked fruit, not poisoned.
        var isGood: Bool { kind.isLikedByDragon && !isPoisoned }
    }

    /// What happened this frame, for the sounds, the story and the tally.
    enum Event: Equatable {
        case ate(FruitKind)
        case refused(FruitKind)
        /// Ate a poisoned fruit: a heart lost.
        case poisoned(FruitKind)
        case burned(FruitKind, wasPoisoned: Bool)
        /// The wave's goal is eaten: a pause, then the next one (its index).
        case waveCleared(next: Int)
        /// Out of hearts: the dragon rests, then the wave starts over.
        case exhausted
        /// The last wave eaten: the dragon is full.
        case finished
    }

    enum Phase: Equatable {
        case playing
        /// Between two waves: the sky clears, the next wave's hint shows.
        case waveCleared
        case exhausted
        case finished
    }

    /// One wave: how many fruit to eat, what the sky holds, how forgiving the aim is.
    struct Wave: Equatable {
        var goal: Int
        var bananaShare: Float
        var poisonShare: Float
        /// Closer than this (and in front of the mouth) a good fruit drifts to it (m).
        var pullRadius: Float
    }

    enum Settings {
        /// Fruit in the sky at a time.
        static let count = 12
        /// The fruit the dragon likes, found in the sky.
        static let liked: [FruitKind] = [.apple, .pineapple, .pomegranate, .orange]
        /// The waves, in order: first only good fruit (learn to steer), then bananas, then poison, then all of it
        /// with less help aiming.
        static let waves: [Wave] = [
            Wave(goal: 3, bananaShare: 0, poisonShare: 0, pullRadius: 3.2),
            Wave(goal: 4, bananaShare: 0.3, poisonShare: 0, pullRadius: 2.6),
            Wave(goal: 4, bananaShare: 0.15, poisonShare: 0.3, pullRadius: 2.1),
            Wave(goal: 5, bananaShare: 0.15, poisonShare: 0.45, pullRadius: 1.6)
        ]
        /// Fruit to eat over the whole feast: a petal each in the medallion (`Shamseh`), 16 like a classic shamseh.
        static var totalGoal: Int { waves.map(\.goal).reduce(0, +) }
        /// The dragon's hearts: each poisoned fruit costs one.
        static let hearts = 3
        /// Where new fruit appear in front of the player (ride space, m): ahead, to the sides, above and below
        /// the dragon's mouth.
        static let ahead: ClosedRange<Float> = 16...36
        static let side: Float = 6.5
        static let height: ClosedRange<Float> = -2.5...2.2
        /// The first fruit of a wave start closer, so there is something to eat at once.
        static let firstAhead: ClosedRange<Float> = 9...36
        /// A fruit this close to the mouth is bitten (m).
        static let biteRadius: Float = 1.1
        static let pullSpeed: Float = 2.5
        /// Swallowing, a spat banana's flight, burning, fading out (s).
        static let eatDuration: Float = 0.35
        static let spitDuration: Float = 1.6
        static let burnDuration: Float = 0.6
        static let fadeDuration: Float = 0.8
        /// A fruit left this far behind the player, or this far away, comes back ahead (m).
        static let behind: Float = 4
        static let farAway: Float = 60
        /// The dragon opens its jaws for a good fruit within this distance (m), and how long it shakes its head
        /// after a banana, and how long a poisoned fruit makes it sick (s).
        static let appetiteRange: Float = 6
        static let disgustDuration: Float = 1.8
        static let sicknessDuration: Float = 3
        /// The pause between two waves, and the dragon's rest when exhausted (s).
        static let breakDuration: Float = 3.5
        static let restDuration: Float = 4
        /// The fire: how long a breath lasts, how long until the next one, how far it reaches (m) and how wide
        /// (half-angle around the flight's direction, radians; a fruit counts with its own size).
        static let fireDuration: Float = 0.9
        static let fireCooldown: Float = 2.5
        static let fireRange: Float = 14
        static let fireAngle: Float = 0.2
        static let fruitRadius: Float = 0.55
    }

    private(set) var plants: [Plant] = []
    /// 0...1: how wide the dragon opens its jaws for the next good fruit.
    private(set) var appetite: Float = 0
    /// 1 right after a banana, back to 0 over `Settings.disgustDuration`.
    private(set) var disgust: Float = 0
    /// 1 right after a poisoned fruit, back to 0 over `Settings.sicknessDuration`: it coughs smoke and flies slower.
    private(set) var sickness: Float = 0
    /// The current wave (index in `Settings.waves`) and the fruit eaten in it.
    private(set) var wave = 0
    private(set) var eaten = 0
    private(set) var hearts = Settings.hearts
    private(set) var phase = Phase.playing
    /// Over the whole feast: bananas spat out, poisoned fruit eaten, fruit burnt.
    private(set) var bananas = 0
    private(set) var poisoned = 0
    private(set) var burned = 0
    /// Seconds in the current phase, and since the last breath of fire.
    private var phaseTime: Float = 0
    private var fireTime: Float = .infinity

    /// Fills the sky in front of the player with the first wave.
    init(ride: DragonRide, using random: inout some RandomNumberGenerator) {
        fill(ride: ride, using: &random)
    }

    var currentWave: Wave { Settings.waves[min(wave, Settings.waves.count - 1)] }
    /// The fire is out and can be breathed again (not once the feast is over).
    var isFireReady: Bool { fireTime >= Settings.fireCooldown && phase != .finished }
    var isBreathingFire: Bool { fireTime < Settings.fireDuration }
    /// 0...1: the breath of fire now (it flares up, holds, dies down).
    var fire: Float {
        guard isBreathingFire else { return 0 }
        let rise = min(fireTime / 0.12, 1)
        let fall = min((Settings.fireDuration - fireTime) / 0.25, 1)
        return min(rise, fall)
    }
    /// 0...1: how weak the dragon is (sick, or exhausted): it flies slower.
    var weakness: Float { phase == .exhausted ? 1 : 0.6 * sickness }

    /// What the tally shows.
    var progress: FeastProgress {
        FeastProgress(wave: wave, waveCount: Settings.waves.count, eaten: eaten, goal: currentWave.goal,
                      hearts: hearts, maxHearts: Settings.hearts, phase: phase, isFireReady: isFireReady,
                      bananas: bananas, poisoned: poisoned, burned: burned)
    }

    /// The player snapped their fingers: the dragon breathes fire, if it can. Returns whether it did.
    mutating func breatheFire() -> Bool {
        guard isFireReady else { return false }
        fireTime = 0
        return true
    }

    /// Advances the fruit and the waves. `mouth`: the dragon's mouth in sky space (it moves with the ride).
    mutating func update(deltaTime: Float, mouth: SIMD3<Float>, ride: DragonRide,
                         using random: inout some RandomNumberGenerator) -> [Event] {
        var events: [Event] = []
        disgust = max(0, disgust - deltaTime / Settings.disgustDuration)
        sickness = max(0, sickness - deltaTime / Settings.sicknessDuration)
        fireTime += deltaTime
        phaseTime += deltaTime
        advancePhase(ride: ride, using: &random)

        var nearest = Float.infinity
        for index in plants.indices {
            var plant = plants[index]
            plant.spin += deltaTime * (plant.isPoisoned ? 0.25 : 0.6)
            switch plant.state {
            case .floating:
                if isBreathingFire && Self.isInFire(plant.position, mouth: mouth, ride: ride) {
                    plant.state = .burnt(progress: 0)
                    burned += 1
                    events.append(.burned(plant.kind, wasPoisoned: plant.isPoisoned))
                    break
                }
                let (event, reach) = float(&plant, deltaTime: deltaTime, mouth: mouth, ride: ride, using: &random)
                if let event { events += bite(event) }
                if let reach { nearest = min(nearest, reach) }
            case .eaten(let progress):
                plant.position = mouth
                finish(&plant, progress: progress + deltaTime / Settings.eatDuration, ride: ride, using: &random) {
                    .eaten(progress: $0)
                }
            case .spat(let progress, var velocity):
                velocity.y -= 4 * deltaTime
                plant.position += velocity * deltaTime
                plant.spin += deltaTime * 8
                finish(&plant, progress: progress + deltaTime / Settings.spitDuration, ride: ride, using: &random) {
                    .spat(progress: $0, velocity: velocity)
                }
            case .burnt(let progress):
                plant.position += ride.forward * ride.speed * 0.6 * deltaTime
                finish(&plant, progress: progress + deltaTime / Settings.burnDuration, ride: ride, using: &random) {
                    .burnt(progress: $0)
                }
            case .fading(let progress):
                plant.state = .fading(progress: min(progress + deltaTime / Settings.fadeDuration, 1))
            }
            plants[index] = plant
        }
        let wanted = nearest.isFinite ? min(max(1 - (nearest - Settings.biteRadius) / Settings.appetiteRange, 0), 1) : 0
        appetite += (wanted - appetite) * min(deltaTime * 6, 1)
        return events
    }

    // MARK: - Waves

    /// The pause between waves and the dragon's rest end: the next wave (or the same, from the start) fills the sky.
    private mutating func advancePhase(ride: DragonRide, using random: inout some RandomNumberGenerator) {
        switch phase {
        case .waveCleared where phaseTime >= Settings.breakDuration:
            wave += 1
            eaten = 0
            start(.playing, ride: ride, using: &random)
        case .exhausted where phaseTime >= Settings.restDuration:
            eaten = 0
            hearts = Settings.hearts
            start(.playing, ride: ride, using: &random)
        default:
            break
        }
    }

    private mutating func start(_ next: Phase, ride: DragonRide, using random: inout some RandomNumberGenerator) {
        phase = next
        phaseTime = 0
        if next == .playing { fill(ride: ride, using: &random) } else { clearSky() }
    }

    /// A new sky for the current wave, its first fruit close.
    private mutating func fill(ride: DragonRide, using random: inout some RandomNumberGenerator) {
        plants = (0..<Settings.count).map { index in
            newPlant(id: index, ride: ride, ahead: Settings.firstAhead, using: &random)
        }
    }

    /// The consequences of a bite: counting, a heart lost, the wave cleared or the dragon exhausted.
    private mutating func bite(_ event: Event) -> [Event] {
        var events = [event]
        switch event {
        case .ate:
            eaten += 1
            if eaten >= currentWave.goal {
                let isLast = wave >= Settings.waves.count - 1
                events.append(isLast ? .finished : .waveCleared(next: wave + 1))
                phase = isLast ? .finished : .waveCleared
                phaseTime = 0
                clearSky()
            }
        case .poisoned:
            poisoned += 1
            hearts = max(hearts - 1, 0)
            sickness = 1
            if hearts == 0 {
                events.append(.exhausted)
                phase = .exhausted
                phaseTime = 0
                clearSky()
            }
        case .refused:
            bananas += 1
        case .burned, .waveCleared, .exhausted, .finished:
            break
        }
        return events
    }

    /// The wave is over: what still floats fades away (the fruit being bitten is written back by `update`).
    private mutating func clearSky() {
        for index in plants.indices where plants[index].isFloating {
            plants[index].state = .fading(progress: 0)
        }
    }

    /// A fruit done being eaten, spat or burnt comes back ahead, but only while the wave is on.
    private mutating func finish(_ plant: inout Plant, progress: Float, ride: DragonRide,
                                 using random: inout some RandomNumberGenerator,
                                 state: (Float) -> PlantState) {
        guard progress >= 1 else {
            plant.state = state(progress)
            return
        }
        plant = phase == .playing
            ? newPlant(id: plant.id, ride: ride, ahead: Settings.ahead, using: &random)
            : Plant(id: plant.id, kind: plant.kind, isPoisoned: plant.isPoisoned, position: plant.position,
                    state: .fading(progress: 1), spin: plant.spin)
    }

    // MARK: - Fruit

    /// A floating fruit: bitten when it reaches the mouth (eaten, spat out, or poisoning the dragon), pulled in when
    /// it is close and good, sent back ahead when left behind. `reach`: its distance from the mouth (m) when it is
    /// a good fruit in front of it.
    private mutating func float(_ plant: inout Plant, deltaTime: Float, mouth: SIMD3<Float>, ride: DragonRide,
                                using random: inout some RandomNumberGenerator) -> (event: Event?, reach: Float?) {
        let toMouth = mouth - plant.position
        let distance = simd_length(toMouth)
        if distance < Settings.biteRadius, phase == .playing {
            if plant.kind.isLikedByDragon {
                plant.state = .eaten(progress: 0)
                return (plant.isPoisoned ? .poisoned(plant.kind) : .ate(plant.kind), nil)
            }
            // Spat forward and to one side, the way it came from.
            let side = simd_normalize(simd_cross(ride.forward, SIMD3(0, 1, 0)))
                * (Bool.random(using: &random) ? 1 : -1)
            plant.state = .spat(progress: 0, velocity: ride.forward * ride.speed * 0.5 + side * 4
                                + SIMD3(0, 2.5, 0))
            disgust = 1
            return (.refused(plant.kind), nil)
        }
        var reach: Float?
        // Only good fruit drift to the mouth: the aim's help never feeds it poison.
        if plant.isGood, simd_dot(-toMouth, ride.forward) > 0 {
            reach = distance
            if distance < currentWave.pullRadius {
                plant.position += toMouth / distance * min(Settings.pullSpeed * deltaTime, distance)
            }
        }
        let seen = ride.rideFromSky(plant.position)
        if seen.z > Settings.behind || simd_length(seen) > Settings.farAway {
            plant = newPlant(id: plant.id, ride: ride, ahead: Settings.ahead, using: &random)
        }
        return (nil, reach)
    }

    /// In the cone of fire in front of the mouth, along the flight.
    static func isInFire(_ point: SIMD3<Float>, mouth: SIMD3<Float>, ride: DragonRide) -> Bool {
        let offset = point - mouth
        let along = simd_dot(offset, ride.forward)
        guard along > -Settings.fruitRadius, along < Settings.fireRange else { return false }
        let across = simd_length(offset - ride.forward * along)
        return across < max(along, 0) * tan(Settings.fireAngle) + Settings.fruitRadius
    }

    #if DEBUG
    /// Tests: puts fruit `index` at `position`, floating, of `kind` (poisoned or not) when given.
    mutating func place(plant index: Int, at position: SIMD3<Float>, kind: FruitKind? = nil,
                        isPoisoned: Bool? = nil) {
        plants[index].position = position
        plants[index].state = .floating
        if let kind { plants[index].kind = kind }
        if let isPoisoned { plants[index].isPoisoned = isPoisoned }
    }
    #endif

    /// A new fruit for the current wave somewhere in front of the player, at the dragon's mouth's height or around
    /// it: a banana, a poisoned fruit or a good one, in the wave's shares.
    private func newPlant(id: Int, ride: DragonRide, ahead: ClosedRange<Float>,
                          using random: inout some RandomNumberGenerator) -> Plant {
        let roll = Float.random(in: 0..<1, using: &random)
        let wave = currentWave
        let isBanana = roll < wave.bananaShare
        let isPoisoned = !isBanana && roll < wave.bananaShare + wave.poisonShare
        let kind = isBanana ? FruitKind.banana : Settings.liked.randomElement(using: &random) ?? .apple
        let seen = SIMD3(Float.random(in: -Settings.side...Settings.side, using: &random),
                         Float.random(in: Settings.height, using: &random),
                         -Float.random(in: ahead, using: &random))
        return Plant(id: id, kind: kind, isPoisoned: isPoisoned, position: ride.skyFromRide(seen),
                     spin: Float.random(in: 0..<(2 * .pi), using: &random))
    }
}

/// The feast as the tally shows it (set on the story only when it changes).
struct FeastProgress: Equatable {
    var wave = 0
    var waveCount = DragonFeast.Settings.waves.count
    var eaten = 0
    var goal = DragonFeast.Settings.waves[0].goal
    var hearts = DragonFeast.Settings.hearts
    var maxHearts = DragonFeast.Settings.hearts
    var phase = DragonFeast.Phase.playing
    var isFireReady = true
    var bananas = 0
    var poisoned = 0
    var burned = 0
}

extension FruitKind {
    /// The dragon eats every fruit but bananas.
    var isLikedByDragon: Bool { self != .banana }
}
