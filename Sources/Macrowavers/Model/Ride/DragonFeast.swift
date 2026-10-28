import Foundation
import simd

/// Chapter II on the dragon's back: fruit float among the clouds and the player steers the dragon into them to feed
/// it. It eats the fruit it likes and spits out the bananas (it doesn't like them: a waste of time); a poisoned fruit
/// makes it sick and costs one of its hearts. A snap of the fingers makes it breathe fire, burning the fruit in front
/// of it: the way to clear poisoned ones off the way (a good one burnt is lost). Out of hearts, the dragon is
/// exhausted: it loses some of the fruit it ate and rests. `Settings.totalGoal` fruit eaten, it is full.
///
/// No waves and no pauses: the sky grows harder as the player does well (`difficulty`, 0...1). Each fruit eaten
/// raises it, more on a streak; a poisoned fruit lowers it, and so does a long time without eating. It sets what the
/// new fruit are (bananas, then poison), how much the aim is helped and how much the fruit dodge (`Level`): a good
/// player reaches the hard sky in a few fruit and is done quickly, one who struggles gets help, so nobody flies for
/// long (the ride's flight can make players dizzy).
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
        /// Leaving the sky while the dragon rests (or at the end): fading as `progress` goes 0...1, then hidden.
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
        /// The way it dodges, from side to side across the flight (sky space, unit), and where in its swing it is.
        var swayAxis = SIMD3<Float>(1, 0, 0)
        var swayPhase: Float = 0

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
        /// The sky reached a harder stage for the first time (its index in `Settings.levels`): its hint shows.
        case stageReached(Int)
        /// Out of hearts: the dragon loses `lost` of the fruit it ate, rests, then flies on.
        case exhausted(lost: Int)
        /// The goal eaten: the dragon is full.
        case finished
    }

    enum Phase: Equatable {
        case playing
        case exhausted
        case finished
    }

    private(set) var plants: [Plant] = []
    /// 0...1: how wide the dragon opens its jaws for the next good fruit.
    private(set) var appetite: Float = 0
    /// 1 right after a banana, back to 0 over `Settings.disgustDuration`.
    private(set) var disgust: Float = 0
    /// 1 right after a poisoned fruit, back to 0 over `Settings.sicknessDuration`: it coughs smoke and flies slower.
    private(set) var sickness: Float = 0
    /// How hard the sky is, 0...1 (see the type's description).
    private(set) var difficulty: Float = 0
    /// The hardest stage reached so far (index in `Settings.levels`): its hint has been shown.
    private(set) var stage = 0
    /// Good fruit eaten in a row (no banana, no poison in between).
    private(set) var streak = 0
    /// Fruit eaten over the whole feast (less those lost when exhausted).
    private(set) var eaten = 0
    private(set) var hearts = Settings.hearts
    private(set) var phase = Phase.playing
    /// Over the whole feast: bananas spat out, poisoned fruit eaten, fruit burnt.
    private(set) var bananas = 0
    private(set) var poisoned = 0
    private(set) var burned = 0
    /// Seconds in the current phase, since the last breath of fire, since the last fruit eaten, and in all.
    private var phaseTime: Float = 0
    private var fireTime: Float = .infinity
    private var hungerTime: Float = 0
    private var time: Float = 0

    /// Fills the sky in front of the player with the first, easiest fruit.
    init(ride: DragonRide, using random: inout some RandomNumberGenerator) {
        fill(ride: ride, using: &random)
    }

    /// What the sky holds now.
    var level: Level { Level.at(difficulty) }
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
        FeastProgress(stage: stage, eaten: eaten, goal: Settings.totalGoal, hearts: hearts,
                      maxHearts: Settings.hearts, phase: phase, isFireReady: isFireReady, bananas: bananas,
                      poisoned: poisoned, burned: burned)
    }

    /// The player snapped their fingers: the dragon breathes fire, if it can. Returns whether it did.
    mutating func breatheFire() -> Bool {
        guard isFireReady else { return false }
        fireTime = 0
        return true
    }

    /// Advances the fruit and the difficulty. `mouth`: the dragon's mouth in sky space (it moves with the ride).
    mutating func update(deltaTime: Float, mouth: SIMD3<Float>, ride: DragonRide,
                         using random: inout some RandomNumberGenerator) -> [Event] {
        var events: [Event] = []
        disgust = max(0, disgust - deltaTime / Settings.disgustDuration)
        sickness = max(0, sickness - deltaTime / Settings.sicknessDuration)
        fireTime += deltaTime
        phaseTime += deltaTime
        time += deltaTime
        relieveHunger(deltaTime: deltaTime)
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

    // MARK: - Difficulty

    /// The dragon's rest ends: hearts back, a new sky.
    private mutating func advancePhase(ride: DragonRide, using random: inout some RandomNumberGenerator) {
        guard phase == .exhausted, phaseTime >= Settings.restDuration else { return }
        hearts = Settings.hearts
        phase = .playing
        phaseTime = 0
        hungerTime = 0
        fill(ride: ride, using: &random)
    }

    /// A new sky at the current difficulty, its first fruit close.
    private mutating func fill(ride: DragonRide, using random: inout some RandomNumberGenerator) {
        plants = (0..<Settings.count).map { index in
            newPlant(id: index, ride: ride, ahead: Settings.firstAhead, using: &random)
        }
    }

    /// The sky grows harder by `amount`; a stage reached for the first time says so.
    private mutating func harden(by amount: Float) -> [Event] {
        difficulty = min(difficulty + amount, 1)
        let reached = Settings.levels.dropLast().lastIndex { $0.start <= difficulty } ?? 0
        guard reached > stage else { return [] }
        stage = reached
        return [.stageReached(reached)]
    }

    /// A player who has not fed the dragon for a while gets help: the sky grows easier.
    private mutating func relieveHunger(deltaTime: Float) {
        guard phase == .playing else { return }
        hungerTime += deltaTime
        if hungerTime > Settings.reliefDelay { ease(by: Settings.reliefRate * deltaTime) }
    }

    /// The sky grows easier by `amount` (stages already reached keep their hints shown).
    private mutating func ease(by amount: Float) {
        difficulty = max(difficulty - amount, 0)
    }

    /// The consequences of a bite: counting, the difficulty, a heart lost, the dragon full or exhausted.
    private mutating func bite(_ event: Event) -> [Event] {
        var events = [event]
        switch event {
        case .ate:
            eaten += 1
            streak += 1
            hungerTime = 0
            if eaten >= Settings.totalGoal {
                events.append(.finished)
                phase = .finished
                phaseTime = 0
                clearSky()
            } else {
                let bonus = Settings.streakBonus * Float(min(streak - 1, Settings.longestStreakBonus))
                events += harden(by: Settings.rise + bonus)
            }
        case .poisoned:
            poisoned += 1
            hearts = max(hearts - 1, 0)
            sickness = 1
            streak = 0
            ease(by: Settings.poisonRelief)
            if hearts == 0 {
                let lost = min(Settings.exhaustionCost, eaten)
                eaten -= lost
                ease(by: Settings.exhaustionRelief)
                events.append(.exhausted(lost: lost))
                phase = .exhausted
                phaseTime = 0
                clearSky()
            }
        case .refused:
            bananas += 1
            streak = 0
        case .burned, .stageReached, .exhausted, .finished:
            break
        }
        return events
    }

    /// The dragon rests or is full: what still floats fades away (the fruit being bitten is written back by
    /// `update`).
    private mutating func clearSky() {
        for index in plants.indices where plants[index].isFloating {
            plants[index].state = .fading(progress: 0)
        }
    }

    /// A fruit done being eaten, spat or burnt comes back ahead, but only while the feast is on.
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
    /// it is close and good, swinging from side to side in a hard sky, sent back ahead when left behind. `reach`: its
    /// distance from the mouth (m) when it is a good fruit in front of it.
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
        let level = self.level
        // Only good fruit drift to the mouth: the aim's help never feeds it poison.
        var isPulled = false
        if plant.isGood, simd_dot(-toMouth, ride.forward) > 0 {
            reach = distance
            if distance < level.pullRadius {
                plant.position += toMouth / distance * min(Settings.pullSpeed * deltaTime, distance)
                isPulled = true
            }
        }
        // The swing's speed (the derivative of `sway · sin`): a fruit being pulled in stops dodging.
        if level.sway > 0, !isPulled {
            let rate = 2 * Float.pi / Settings.swayPeriod
            plant.position += plant.swayAxis * (level.sway * rate * cos(time * rate + plant.swayPhase) * deltaTime)
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
    /// Tests: sets how hard the sky is.
    mutating func setDifficulty(_ value: Float) {
        difficulty = value
    }

    /// Tests: puts fruit `index` at `position`, floating, of `kind` (poisoned or not) when given.
    mutating func place(plant index: Int, at position: SIMD3<Float>, kind: FruitKind? = nil,
                        isPoisoned: Bool? = nil) {
        plants[index].position = position
        plants[index].state = .floating
        if let kind { plants[index].kind = kind }
        if let isPoisoned { plants[index].isPoisoned = isPoisoned }
    }
    #endif

    /// A new fruit for the current sky somewhere in front of the player, at the dragon's mouth's height or around
    /// it: a banana, a poisoned fruit or a good one, in the level's shares.
    private func newPlant(id: Int, ride: DragonRide, ahead: ClosedRange<Float>,
                          using random: inout some RandomNumberGenerator) -> Plant {
        let roll = Float.random(in: 0..<1, using: &random)
        let level = self.level
        let isBanana = roll < level.bananaShare
        let isPoisoned = !isBanana && roll < level.bananaShare + level.poisonShare
        let kind = isBanana ? FruitKind.banana : Settings.liked.randomElement(using: &random) ?? .apple
        let seen = SIMD3(Float.random(in: -Settings.side...Settings.side, using: &random),
                         Float.random(in: Settings.height, using: &random),
                         -Float.random(in: ahead, using: &random))
        // Across the flight, level: it dodges sideways, never towards the player.
        let across = simd_cross(ride.forward, SIMD3(0, 1, 0))
        return Plant(id: id, kind: kind, isPoisoned: isPoisoned, position: ride.skyFromRide(seen),
                     spin: Float.random(in: 0..<(2 * .pi), using: &random),
                     swayAxis: simd_length(across) > 1e-3 ? simd_normalize(across) : SIMD3(1, 0, 0),
                     swayPhase: Float.random(in: 0..<(2 * .pi), using: &random))
    }
}

extension DragonFeast {
    /// What the sky holds at a difficulty: the shares of bananas and poisoned fruit among the new fruit, how
    /// forgiving the aim is, how far the fruit dodge.
    struct Level: Equatable {
        /// The difficulty this level starts at (0...1).
        var start: Float
        var bananaShare: Float
        var poisonShare: Float
        /// Closer than this (and in front of the mouth) a good fruit drifts to it (m).
        var pullRadius: Float
        /// How far the fruit swing to either side (m).
        var sway: Float

        /// The sky at `difficulty`: between the levels it lies in, each value eased from one to the next, but a kind
        /// of fruit the lower level has none of stays out until the next level begins (its hint comes with it).
        static func at(_ difficulty: Float) -> Level {
            let levels = Settings.levels
            guard let upper = levels.firstIndex(where: { $0.start > difficulty }) else { return levels[levels.count - 1] }
            guard upper > 0 else { return levels[0] }
            let low = levels[upper - 1]
            let high = levels[upper]
            let amount = (difficulty - low.start) / (high.start - low.start)
            func mix(_ from: Float, _ to: Float) -> Float { from + (to - from) * amount }
            return Level(start: difficulty,
                         bananaShare: low.bananaShare == 0 ? 0 : mix(low.bananaShare, high.bananaShare),
                         poisonShare: low.poisonShare == 0 ? 0 : mix(low.poisonShare, high.poisonShare),
                         pullRadius: mix(low.pullRadius, high.pullRadius), sway: mix(low.sway, high.sway))
        }
    }

    enum Settings {
        /// Fruit in the sky at a time.
        static let count = 12
        /// The fruit the dragon likes, found in the sky.
        static let liked: [FruitKind] = [.apple, .pineapple, .pomegranate, .orange]
        /// The sky's stages, by difficulty: first only good fruit (learn to steer), then bananas, then poison, then
        /// all of it, dodging a little, with less help aiming. The last one is the hardest sky (difficulty 1), not a
        /// stage. The hard sky is hard in what to eat and what to burn, not in aiming: less help aiming and wider
        /// swings meant many more turns to line up each fruit (the turns are what makes riders dizzy) and a longer
        /// ride, with the aim helped down to 1.2 m and swings of 1 m, ~40 s more at the hardest sky.
        static let levels: [Level] = [
            Level(start: 0, bananaShare: 0, poisonShare: 0, pullRadius: 3.2, sway: 0),
            Level(start: 0.15, bananaShare: 0.3, poisonShare: 0, pullRadius: 2.8, sway: 0),
            Level(start: 0.4, bananaShare: 0.15, poisonShare: 0.3, pullRadius: 2.4, sway: 0.15),
            Level(start: 0.75, bananaShare: 0.1, poisonShare: 0.45, pullRadius: 2.1, sway: 0.3),
            Level(start: 1, bananaShare: 0.1, poisonShare: 0.55, pullRadius: 2, sway: 0.4)
        ]
        /// The stages with a hint of their own (every level but the hardest sky).
        static var stageCount: Int { levels.count - 1 }
        /// Fruit to eat over the whole feast: a petal each in the medallion (`Shamseh`), a ten-pointed shamseh.
        static let totalGoal = 10
        /// How much each fruit eaten raises the difficulty, and the extra for each fruit before it in a streak (eaten
        /// without a banana or a poisoned fruit in between), up to `longestStreakBonus` of them. Without a slip,
        /// bananas come with the 2nd fruit, poison with the 3rd, the last stretch with the 5th and the hardest sky
        /// with the 7th: the last four are eaten in it.
        static let rise: Float = 0.1
        static let streakBonus: Float = 0.04
        static let longestStreakBonus = 2
        /// How much a poisoned fruit lowers it, and exhaustion.
        static let poisonRelief: Float = 0.12
        static let exhaustionRelief: Float = 0.25
        /// Help for a player who struggles: after this long without eating (s), the difficulty falls this fast (1/s).
        static let reliefDelay: Float = 10
        static let reliefRate: Float = 0.02
        /// Fruit lost (and petals uncoloured) when the dragon is exhausted.
        static let exhaustionCost = 2
        /// How long a fruit's swing from side to side and back lasts (s).
        static let swayPeriod: Float = 4
        /// The dragon's hearts: each poisoned fruit costs one.
        static let hearts = 3
        /// Where new fruit appear in front of the player (ride space, m): ahead, to the sides, above and below
        /// the dragon's mouth.
        static let ahead: ClosedRange<Float> = 16...36
        static let side: Float = 6.5
        static let height: ClosedRange<Float> = -2.5...2.2
        /// The first fruit of a new sky start closer, so there is something to eat at once.
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
        /// The dragon's rest when exhausted (s).
        static let restDuration: Float = 4
        /// The fire: how long a breath lasts, how long until the next one, how far it reaches (m) and how wide
        /// (half-angle around the flight's direction, radians; a fruit counts with its own size).
        static let fireDuration: Float = 0.9
        static let fireCooldown: Float = 2.5
        static let fireRange: Float = 14
        static let fireAngle: Float = 0.2
        static let fruitRadius: Float = 0.55
    }
}

/// The feast as the tally shows it (set on the story only when it changes).
struct FeastProgress: Equatable {
    /// The hardest stage reached (its hint shows when it is reached).
    var stage = 0
    var eaten = 0
    var goal = DragonFeast.Settings.totalGoal
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
