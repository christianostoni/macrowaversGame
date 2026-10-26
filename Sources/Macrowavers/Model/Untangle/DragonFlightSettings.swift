import Foundation

/// The dragon's manoeuvres and the flight's tuning.
extension DragonFlight {
    enum Maneuver: Equatable {
        /// Leaves the play area climbing with strong wing beats.
        case takeoff
        /// Glides in circles around the player, rising and falling.
        case cruise
        /// Dive: passes beside the player, lower down, and climbs again.
        case swoop
        /// Stops in front of the player (where they are looking), looks at them and roars with a burst of fire
        /// upwards.
        case hover
        /// Vertical loop.
        case loop
        /// Captive: circles the island's tree along `OrbitPath` until it is called.
        case orbit
        /// Receives the elixir: slows down to a stop on its path around the tree (`holdBraking`), the body still on
        /// it, until it is called.
        case hold
        /// Called: flies to the player and stops in front of them, looking at them.
        case approach
        /// Settles: the head retraces the knot from the tail, the body follows it
        /// and in the end lies exactly in the shape of `landingKnot`.
        case land
        /// Leaves: climbs and moves away into the sky, faster and faster.
        case depart

        var duration: Float {
            switch self {
            case .takeoff: 2.2
            case .cruise: 6
            case .swoop: 3
            case .hover: 3.2
            case .loop: 3
            case .orbit, .hold: .infinity
            case .approach: 5
            // Depends on the path length: see `landingProgress`.
            case .land: .infinity
            case .depart: 6
            }
        }

        /// At the end the flight stops (the dragon has landed or is gone) instead of picking another manoeuvre.
        var isFinal: Bool { self == .land || self == .depart }

        /// Manoeuvres "in the room": they respect the altitude and the maximum distance from the player.
        var staysInRoom: Bool {
            switch self {
            case .takeoff, .cruise, .swoop, .hover, .loop: true
            case .orbit, .hold, .approach, .land, .depart: false
            }
        }
    }

    struct Settings {
        var speed: Float = 0.75
        /// How quickly the head changes direction (higher = tighter turns).
        var steering: Float = 2.2
        /// Horizontal distance from the player within which it flies.
        var orbitRadius: ClosedRange<Float> = 1.1...2.0
        /// Flight altitudes (m above the floor).
        var altitude: ClosedRange<Float> = 0.9...2.1
        /// The dragon never gets closer than this to the player's head (comfort).
        var personalSpace: Float = 0.7
        /// How far from the player's eyes it stops when it arrives (beyond the personal space).
        var approachDistance: Float = 1.0
        /// Speed of the head while it traces the knot to settle.
        var landingSpeed: Float = 0.65
        /// Half-angle (radians) of the arc in front of the player where it cruises; `nil` = full circles around them.
        var frontArc: Float?
        /// How far in front of the player's eyes it hovers to thank them.
        var hoverDistance: Float = 1.3
        /// Room manoeuvres are kept inside the flight volume (`orbitRadius` and `altitude`) plus this margin.
        var boundsMargin: Float = 0.3
        /// Distance travelled while departing over which it fades out: at the far end the flight is over.
        var departFade: ClosedRange<Float> = 0.4...1.8

        /// Free at last: a short, calm farewell that never leaves the space in front of the player.
        /// It cruises in a 110° arc 1.2–1.6 m away, hovers 1.35 m in front of their eyes and fades out within
        /// ~2 m as it departs, so it never flies behind them or through the room's walls and ceiling.
        static let farewell: Settings = {
            var settings = Settings()
            settings.orbitRadius = 1.2...1.6
            settings.altitude = 1.0...1.8
            settings.personalSpace = 0.9
            settings.frontArc = 55 * .pi / 180
            settings.hoverDistance = 1.35
            settings.boundsMargin = 0.15
            return settings
        }()
    }
}
