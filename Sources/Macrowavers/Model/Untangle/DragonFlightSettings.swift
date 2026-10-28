import Foundation

/// The dragon's manoeuvres and the flight's tuning.
extension DragonFlight {
    enum Maneuver: Equatable {
        /// Gliding with the player on its back: only drawn on the ride (`DragonRideSystem` poses the rig with it,
        /// feeding on the wing); `DragonFlight` never flies it.
        case cruise
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

        var duration: Float {
            switch self {
            case .cruise, .orbit, .hold: .infinity
            case .approach: 5
            // Depends on the path length: see `landingProgress`.
            case .land: .infinity
            }
        }

        /// At the end the flight stops (the dragon has landed) instead of starting the manoeuvre over.
        var isFinal: Bool { self == .land }
    }

    struct Settings {
        var speed: Float = 0.75
        /// How quickly the head changes direction (higher = tighter turns).
        var steering: Float = 2.2
        /// The dragon never gets closer than this to the player's head (comfort).
        var personalSpace: Float = 0.7
        /// How far from the player's eyes it stops when it arrives (beyond the personal space).
        var approachDistance: Float = 1.0
        /// Speed of the head while it traces the knot to settle.
        var landingSpeed: Float = 0.65
    }
}
