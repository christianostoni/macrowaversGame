import Foundation
import simd

/// One hand-tracking reading, in the immersive scene's space. Built by the RealityKit layer (`HandTracker`)
/// from ARKit's joints; plain values, so the gesture detectors below stay testable without a headset.
struct HandSample: Equatable {
    enum Chirality: Int, CaseIterable {
        case left
        case right
    }

    var chirality: Chirality
    /// ARKit timestamp (s).
    var timestamp: TimeInterval
    /// Middle-finger knuckle: the edge of the hand that chops.
    var knuckle: SIMD3<Float>
    var wrist: SIMD3<Float>
    var thumbTip: SIMD3<Float>
    var indexTip: SIMD3<Float>
    /// Normal of the palm (unit length): turns with the wrist when the player twists.
    var palmNormal: SIMD3<Float>

    /// Wrist → middle knuckle (unit length): the axis the hand rolls around in a twist.
    var handAxis: SIMD3<Float> {
        let axis = knuckle - wrist
        return simd_length(axis) > 1e-5 ? simd_normalize(axis) : SIMD3(0, 0, -1)
    }

    var pinchDistance: Float { simd_distance(thumbTip, indexTip) }
}

/// The pineapple's chop: a hand coming down fast through the fruit (ported from the fruit lab prototype).
struct ChopDetector {
    struct Settings {
        /// Minimum downward speed of the knuckle (m/s).
        var speed: Float = 1.0
        /// Samples further apart than this are a tracking gap, not a movement (s).
        var maxSampleGap: TimeInterval = 0.1
        /// After a chop the same hand cannot chop again for this long (s).
        var cooldown: TimeInterval = 0.3
    }

    /// The fruit to chop, in scene space.
    struct Target {
        var center: SIMD3<Float>
        /// Bottom of the fruit.
        var baseY: Float
        /// Horizontal distance from the centre that still counts as "through the fruit".
        var radius: Float
        /// Height above the base where the hand must be.
        var heightWindow: Float
    }

    private struct HandState {
        var last: HandSample?
        var cooldownUntil: TimeInterval = 0
    }

    let settings: Settings
    private var hands: [HandSample.Chirality: HandState] = [:]

    init(settings: Settings = Settings()) {
        self.settings = settings
    }

    /// Feeds one hand reading; returns true when this reading is a chop through `target`.
    mutating func process(_ sample: HandSample, target: Target) -> Bool {
        var state = hands[sample.chirality] ?? HandState()
        defer { hands[sample.chirality] = state }
        let previous = state.last
        state.last = sample
        guard let previous else { return false }
        let deltaTime = sample.timestamp - previous.timestamp
        // Same reading twice, out of order, or a tracking gap.
        guard deltaTime > 0, deltaTime <= settings.maxSampleGap else { return false }

        let downSpeed = (previous.knuckle.y - sample.knuckle.y) / Float(deltaTime)
        guard downSpeed > settings.speed, sample.timestamp >= state.cooldownUntil else { return false }
        let horizontal = simd_length(SIMD2(sample.knuckle.x - target.center.x, sample.knuckle.z - target.center.z))
        let height = sample.knuckle.y - target.baseY
        guard horizontal <= target.radius, height >= 0, height <= target.heightWindow else { return false }
        state.cooldownUntil = sample.timestamp + settings.cooldown
        return true
    }

    /// Forgets the hands (a new fruit is in front of the player).
    mutating func reset() {
        hands = [:]
    }
}

/// The kalash's twist: thumb and index pinched, the wrist rolls like turning a key, while the player looks at
/// the kalash. Fires once the roll reaches `minimumRoll` within `window` seconds; `progress` tells the player how
/// far they are.
struct TwistDetector {
    struct Settings {
        /// Thumb tip to index tip below this distance = pinching (m).
        var pinchDistance: Float = 0.025
        /// Roll of the wrist needed (radians, either direction).
        var minimumRoll: Float = 45 * .pi / 180
        /// The roll must happen within this time (s).
        var window: TimeInterval = 1.5
        /// Samples further apart than this restart the gesture (s).
        var maxSampleGap: TimeInterval = 0.15
    }

    private struct HandState {
        var last: HandSample?
        /// Roll accumulated since the pinch started, with the time of each step.
        var history: [(time: TimeInterval, roll: Float)] = []
        /// How far this hand's twist is (0…1).
        var progress: Float = 0
    }

    let settings: Settings
    private var hands: [HandSample.Chirality: HandState] = [:]

    /// How far the best hand's twist is (0 = not twisting, 1 = done).
    var progress: Float { hands.values.map(\.progress).max() ?? 0 }

    init(settings: Settings = Settings()) {
        self.settings = settings
    }

    /// Feeds one hand reading; `isLooking` is whether the player looks at the kalash right now.
    /// Returns true when the twist is complete (then the hand starts over).
    mutating func process(_ sample: HandSample, isLooking: Bool) -> Bool {
        var state = hands[sample.chirality] ?? HandState()
        defer { hands[sample.chirality] = state }
        guard isLooking, sample.pinchDistance < settings.pinchDistance else {
            state = HandState()
            return false
        }
        // The same reading again (the frame is faster than the hand tracking): nothing new.
        if let previous = state.last, sample.timestamp == previous.timestamp { return false }
        guard let previous = state.last, sample.timestamp > previous.timestamp,
              sample.timestamp - previous.timestamp <= settings.maxSampleGap else {
            state = HandState(last: sample, history: [(sample.timestamp, 0)])
            return false
        }
        state.last = sample
        let step = Self.roll(from: previous.palmNormal, to: sample.palmNormal, around: sample.handAxis)
        let total = (state.history.last?.roll ?? 0) + step
        state.history.append((sample.timestamp, total))
        state.history.removeAll { sample.timestamp - $0.time > settings.window }

        let rolls = state.history.map(\.roll)
        guard let lowest = rolls.min(), let highest = rolls.max() else { return false }
        let roll = max(total - lowest, highest - total)
        if roll >= settings.minimumRoll {
            state = HandState()
            return true
        }
        state.progress = roll / settings.minimumRoll
        return false
    }

    /// Forgets the hands.
    mutating func reset() {
        hands = [:]
    }

    /// Signed angle (radians) the palm normal turned around `axis`: both normals are projected on the plane
    /// perpendicular to the axis, so bending the wrist or moving the arm does not count as a twist.
    static func roll(from old: SIMD3<Float>, to new: SIMD3<Float>, around axis: SIMD3<Float>) -> Float {
        let oldFlat = old - simd_dot(old, axis) * axis
        let newFlat = new - simd_dot(new, axis) * axis
        guard simd_length(oldFlat) > 1e-4, simd_length(newFlat) > 1e-4 else { return 0 }
        let from = simd_normalize(oldFlat)
        let to = simd_normalize(newFlat)
        return atan2(simd_dot(simd_cross(from, to), axis), simd_dot(from, to))
    }

    /// Whether a head looking along `forward` from `eyes` looks at `target`, within `maximumAngle` (radians).
    /// Generous: visionOS gives the head's direction, not the eyes', and the kalash sits low by the hip.
    static func isLooking(from eyes: SIMD3<Float>, forward: SIMD3<Float>, at target: SIMD3<Float>,
                          maximumAngle: Float = 45 * .pi / 180) -> Bool {
        let direction = target - eyes
        guard simd_length(direction) > 1e-4, simd_length(forward) > 1e-4 else { return false }
        return simd_dot(simd_normalize(direction), simd_normalize(forward)) >= cos(maximumAngle)
    }
}
