import Foundation
import simd

/// Chapter II on the dragon's back: fruit float among the clouds and the player steers the dragon into them to feed
/// it. It eats the fruit it likes and spits out the bananas: it doesn't like bananas.
/// Pure state, no RealityKit, like `DragonRide`: positions are in its sky space; `DragonRideSystem` draws them.
struct DragonFeast {
    /// A fruit floating in the sky.
    struct Plant: Identifiable, Equatable {
        enum State: Equatable {
            case floating
            /// In the dragon's mouth, swallowed as `progress` goes 0...1.
            case eaten(progress: Float)
            /// Spat out: flung away (velocity in sky space, m/s), fading as `progress` goes 0...1.
            case spat(progress: Float, velocity: SIMD3<Float>)
        }

        let id: Int
        var kind: FruitKind
        /// Sky space (m).
        var position: SIMD3<Float>
        var state = State.floating
        /// Its slow tumble (radians), random so the fruit don't turn in step.
        var spin: Float

        var isFloating: Bool { state == .floating }
    }

    /// What happened to a fruit this frame, for the sounds and the story.
    enum Event: Equatable {
        case ate(FruitKind)
        case refused(FruitKind)
    }

    enum Settings {
        /// Fruit in the sky at a time.
        static let count = 12
        /// Share of them that are bananas.
        static let bananaShare: Float = 0.3
        /// The fruit the dragon likes, found in the sky.
        static let liked: [FruitKind] = [.apple, .pineapple, .pomegranate, .orange]
        /// Where new fruit appear in front of the player (ride space, m): ahead, to the sides, above and below
        /// the dragon's mouth.
        static let ahead: ClosedRange<Float> = 16...36
        static let side: Float = 6.5
        static let height: ClosedRange<Float> = -2.5...2.2
        /// The first fruit start closer, so there is something to eat at once.
        static let firstAhead: ClosedRange<Float> = 9...36
        /// A fruit this close to the mouth is bitten (m).
        static let biteRadius: Float = 1.1
        /// Closer than this (and in front of the mouth), a fruit the dragon likes drifts to it: forgiving aim.
        static let pullRadius: Float = 3.2
        static let pullSpeed: Float = 2.5
        /// Swallowing, and a spat banana's flight (s).
        static let eatDuration: Float = 0.35
        static let spitDuration: Float = 1.6
        /// A fruit left this far behind the player, or this far away, comes back ahead (m).
        static let behind: Float = 4
        static let farAway: Float = 60
        /// The dragon opens its jaws for a fruit it likes within this distance (m), and how long it shakes its
        /// head after a banana (s).
        static let appetiteRange: Float = 6
        static let disgustDuration: Float = 1.8
    }

    private(set) var plants: [Plant] = []
    /// 0...1: how wide the dragon opens its jaws for the next fruit.
    private(set) var appetite: Float = 0
    /// 1 right after a banana, back to 0 over `Settings.disgustDuration`.
    private(set) var disgust: Float = 0

    /// Fills the sky in front of the player.
    init(ride: DragonRide, using random: inout some RandomNumberGenerator) {
        plants = (0..<Settings.count).map { index in
            Self.newPlant(id: index, ride: ride, ahead: Settings.firstAhead, using: &random)
        }
    }

    /// Advances the fruit. `mouth`: the dragon's mouth in sky space (it moves with the ride). Returns what the
    /// dragon ate or refused this frame.
    mutating func update(deltaTime: Float, mouth: SIMD3<Float>, ride: DragonRide,
                         using random: inout some RandomNumberGenerator) -> [Event] {
        var events: [Event] = []
        disgust = max(0, disgust - deltaTime / Settings.disgustDuration)
        var nearest = Float.infinity
        for index in plants.indices {
            var plant = plants[index]
            plant.spin += deltaTime * 0.6
            switch plant.state {
            case .floating:
                let toMouth = mouth - plant.position
                let distance = simd_length(toMouth)
                if distance < Settings.biteRadius {
                    if plant.kind.isLikedByDragon {
                        plant.state = .eaten(progress: 0)
                        events.append(.ate(plant.kind))
                    } else {
                        // Spat forward and to one side, the way it came from.
                        let side = simd_normalize(simd_cross(ride.forward, SIMD3(0, 1, 0)))
                            * (Bool.random(using: &random) ? 1 : -1)
                        plant.state = .spat(progress: 0, velocity: ride.forward * ride.speed * 0.5 + side * 4
                                            + SIMD3(0, 2.5, 0))
                        disgust = 1
                        events.append(.refused(plant.kind))
                    }
                } else if plant.kind.isLikedByDragon {
                    let inFront = simd_dot(-toMouth, ride.forward) > 0
                    if inFront {
                        nearest = min(nearest, distance)
                        if distance < Settings.pullRadius {
                            plant.position += toMouth / distance * min(Settings.pullSpeed * deltaTime, distance)
                        }
                    }
                }
                let seen = ride.rideFromSky(plant.position)
                if seen.z > Settings.behind || simd_length(seen) > Settings.farAway {
                    plant = Self.newPlant(id: plant.id, ride: ride, ahead: Settings.ahead, using: &random)
                }
            case .eaten(let progress):
                plant.position = mouth
                let next = progress + deltaTime / Settings.eatDuration
                plant.state = .eaten(progress: min(next, 1))
                if next >= 1 { plant = Self.newPlant(id: plant.id, ride: ride, ahead: Settings.ahead, using: &random) }
            case .spat(let progress, var velocity):
                velocity.y -= 4 * deltaTime
                plant.position += velocity * deltaTime
                plant.spin += deltaTime * 8
                let next = progress + deltaTime / Settings.spitDuration
                plant.state = .spat(progress: min(next, 1), velocity: velocity)
                if next >= 1 { plant = Self.newPlant(id: plant.id, ride: ride, ahead: Settings.ahead, using: &random) }
            }
            plants[index] = plant
        }
        let wanted = nearest.isFinite ? min(max(1 - (nearest - Settings.biteRadius) / Settings.appetiteRange, 0), 1) : 0
        appetite += (wanted - appetite) * min(deltaTime * 6, 1)
        return events
    }

    #if DEBUG
    /// Tests: puts fruit `index` at `position`, floating.
    mutating func place(plant index: Int, at position: SIMD3<Float>) {
        plants[index].position = position
        plants[index].state = .floating
    }
    #endif

    /// A new fruit somewhere in front of the player, at the dragon's mouth's height or around it.
    private static func newPlant(id: Int, ride: DragonRide, ahead: ClosedRange<Float>,
                                 using random: inout some RandomNumberGenerator) -> Plant {
        let isBanana = Float.random(in: 0..<1, using: &random) < Settings.bananaShare
        let kind = isBanana ? FruitKind.banana : Settings.liked.randomElement(using: &random) ?? .apple
        let seen = SIMD3(Float.random(in: -Settings.side...Settings.side, using: &random),
                         Float.random(in: Settings.height, using: &random),
                         -Float.random(in: ahead, using: &random))
        return Plant(id: id, kind: kind, position: ride.skyFromRide(seen),
                     spin: Float.random(in: 0..<(2 * .pi), using: &random))
    }
}

extension FruitKind {
    /// The dragon eats every fruit but bananas.
    var isLikedByDragon: Bool { self != .banana }
}
