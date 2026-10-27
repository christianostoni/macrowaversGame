import Foundation
import simd

/// Keeps the snap that breathes fire from steering the dragon. The hands steer by where they are (`DragonRide`), and
/// a snap is made by one of them: while that hand presses its thumb on its middle finger (the loaded pose) and for a
/// moment after the snap, the steering keeps reading where it was just before, so the dragon does not swerve.
/// A hand left loaded for long (a curled grip on the horns can look like one) steers again after `longestHold`.
/// Pure state: `DragonRideSystem` passes it the hands every frame.
struct SteeringHold: Equatable {
    /// How long a hand stays frozen after it snapped (s): the flick and the hand settling back.
    static let afterSnap: Float = 0.35
    /// The longest a loaded hand stays frozen (s): a snap follows its loaded pose within a second.
    static let longestHold: Float = 0.8

    private struct Hand: Equatable {
        /// Its last position read while free.
        var steady: SIMD3<Float>?
        /// When its current freeze began, and until when it lasts after a snap.
        var frozenSince: Float?
        var frozenUntil: Float = -.infinity
    }

    private var left = Hand()
    private var right = Hand()

    /// The hands to steer with. `left`/`right`: where they are (nil: not tracked); `loaded`: the hands holding the
    /// loaded pose; `snapped`: the hands that snapped this frame; `time`: the ride's clock (s).
    mutating func steering(left leftPoint: SIMD3<Float>?, right rightPoint: SIMD3<Float>?,
                           loaded: Set<HandSample.Chirality>, snapped: Set<HandSample.Chirality>,
                           time: Float) -> (left: SIMD3<Float>?, right: SIMD3<Float>?) {
        (Self.filter(&left, point: leftPoint, isLoaded: loaded.contains(.left), didSnap: snapped.contains(.left),
                     time: time),
         Self.filter(&right, point: rightPoint, isLoaded: loaded.contains(.right), didSnap: snapped.contains(.right),
                     time: time))
    }

    private static func filter(_ hand: inout Hand, point: SIMD3<Float>?, isLoaded: Bool, didSnap: Bool,
                               time: Float) -> SIMD3<Float>? {
        guard let point else {
            hand = Hand()
            return nil
        }
        if didSnap {
            hand.frozenUntil = time + afterSnap
            hand.frozenSince = hand.frozenSince ?? time
        } else if isLoaded {
            hand.frozenSince = hand.frozenSince ?? time
        } else if time >= hand.frozenUntil {
            hand.frozenSince = nil
        }
        let isFrozen = hand.frozenSince.map { time - $0 < longestHold || time < hand.frozenUntil } ?? false
        guard isFrozen, let steady = hand.steady else {
            hand.steady = point
            return point
        }
        return steady
    }
}

extension SnapDetector.Settings {
    /// On the ride the hands also steer: a snap must leave the wrist where it was (within 4 cm), so a quick move of
    /// the horns never breathes fire.
    static var whileSteering: Self {
        var settings = Self()
        settings.maxWristTravel = 0.04
        return settings
    }
}
