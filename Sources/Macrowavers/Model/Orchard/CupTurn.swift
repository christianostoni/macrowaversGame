import Foundation
import simd

/// A hand cupped next to the fruit in front of the player turns it: all four fingers curled like a bowl, the thumb
/// off the index (a pinch is the system's tap and drag), the palm close to the fruit. While that hand holds, every
/// reading gives the turn of the palm since the previous one, which the RealityKit layer applies to the fruit. One
/// hand at a time: the first one to cup holds until it opens or leaves.
struct CupTurn {
    struct Settings {
        /// Bend of every finger that counts as cupped (degrees; about 0 stretched, 180 in a fist).
        var bend: ClosedRange<Float> = 35...120
        /// Once holding, the bend range widens by this much on both sides, so tracking noise does not drop it.
        var keepMargin: Float = 10
        /// Thumb tip to index tip below this is a pinch, not a cup (m).
        var pinchClearance: Float = 0.02
        /// Palm centre to fruit centre to start turning, and to keep turning (m).
        var reach: Float = 0.16
        var keepReach: Float = 0.22
        /// A holding hand that stops looking cupped for less than this still holds (it does not turn meanwhile).
        var grace: TimeInterval = 0.15
        /// Readings further apart than this are a tracking gap: the turn starts over from the new reading (s).
        var maxSampleGap: TimeInterval = 0.1
        /// How quickly the followed palm catches up with the measured one (1/s): smooths the tracking jitter.
        var smoothing: Float = 20
    }

    private struct Hold {
        let chirality: HandSample.Chirality
        /// The palm as followed (smoothed), in scene space.
        var frame: simd_quatf
        var lastTime: TimeInterval
        var lastCupped: TimeInterval
    }

    var settings = Settings()
    private var hold: Hold?

    var isHolding: Bool { hold != nil }
    var holdingHand: HandSample.Chirality? { hold?.chirality }

    /// The latest reading of each tracked hand and the fruit's centre (scene space). Returns how the fruit should
    /// turn (scene space, to apply before its orientation), or nil when no hand turns it.
    mutating func process(_ samples: [HandSample], fruitCentre: SIMD3<Float>) -> simd_quatf? {
        if let current = hold {
            // The holding hand is no longer tracked: it lets go.
            guard let sample = samples.first(where: { $0.chirality == current.chirality }) else {
                hold = nil
                return nil
            }
            return follow(sample, current, fruitCentre: fruitCentre)
        }
        let first = samples.sorted { $0.chirality.rawValue < $1.chirality.rawValue }
            .first { isCupped($0, fruitCentre: fruitCentre, keeping: false) }
        if let first {
            hold = Hold(chirality: first.chirality, frame: first.palmFrame, lastTime: first.timestamp,
                        lastCupped: first.timestamp)
        }
        return nil
    }

    mutating func reset() {
        hold = nil
    }

    private mutating func follow(_ sample: HandSample, _ current: Hold, fruitCentre: SIMD3<Float>) -> simd_quatf? {
        // The frame rate is higher than the tracking rate: the same reading comes back until the next one.
        guard sample.timestamp > current.lastTime else { return nil }
        let gap = sample.timestamp - current.lastTime
        var next = current
        next.lastTime = sample.timestamp
        let isCupped = isCupped(sample, fruitCentre: fruitCentre, keeping: true)
        if isCupped {
            next.lastCupped = sample.timestamp
        } else if sample.timestamp - current.lastCupped > settings.grace {
            hold = nil
            return nil
        }
        guard gap <= settings.maxSampleGap else {
            next.frame = sample.palmFrame
            hold = next
            return nil
        }
        next.frame = simd_slerp(current.frame, sample.palmFrame, 1 - exp(-Float(gap) * settings.smoothing))
        hold = next
        return isCupped ? next.frame * current.frame.inverse : nil
    }

    private func isCupped(_ sample: HandSample, fruitCentre: SIMD3<Float>, keeping: Bool) -> Bool {
        let margin = keeping ? settings.keepMargin : 0
        let bend = (settings.bend.lowerBound - margin)...(settings.bend.upperBound + margin)
        return sample.fingerBends.allSatisfy { bend.contains($0) }
            && simd_distance(sample.thumbTip, sample.indexTip) >= settings.pinchClearance
            && simd_distance(sample.palmCentre, fruitCentre) <= (keeping ? settings.keepReach : settings.reach)
    }
}
