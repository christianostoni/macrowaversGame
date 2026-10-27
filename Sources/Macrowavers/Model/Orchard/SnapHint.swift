import Foundation
import simd

/// The hologram hand that shows how to brew the elixir: with every ingredient in orbit, a ghostly right hand floats
/// under the flask and snaps its fingers, over and over, until the player does the same (`SnapDetector`).
/// Pure maths (Foundation + simd): the `OrchardSystem` keeps one and advances it; its skin is `HandSurface`.
///
/// The hand lives in its own space (metres): the wrist at the origin, the fingers up (+Y), the palm facing +Z, the
/// thumb on +X (a right hand with its palm towards the viewer). Each loop: the open hand, the thumb pressed on the
/// middle finger's pad (the ring and little fingers curled), then, in a flash, the middle finger flicks into the
/// palm as the thumb slides along the index, a hold, and the hand opens again.
///
/// The fingers bend at their three joints (`FingerPose`, the last one at 0.7 of the middle one); the thumb is a
/// fixed first bone (the metacarpal, turned towards the palm as the hand loads) and two phalanges solved to reach a
/// target point (two-bone IK): its tip lands exactly on the middle finger's pad in the loaded pose.
struct SnapHint: Equatable {
    /// The joints of one pose (hand space) and the points the effects need.
    struct Pose: Equatable {
        var thumb: ThumbJoints
        var thumbTip: SIMD3<Float> { thumb.tip }
        /// The pad of the middle finger's last phalanx: where the thumb presses.
        var middlePad: SIMD3<Float>
        var middleTip: SIMD3<Float>
        /// Each finger's three joints after its knuckle (index, middle, ring, little; the last is the fingertip).
        var fingers: [[SIMD3<Float>]]
    }

    /// Seconds of one loop, and when in it the middle finger hits the palm (the snap).
    static let period: Float = 2.8
    static let snapTime: Float = 1.3
    /// How fast the hand fades in and out (s).
    static let fadeDuration: Float = 0.5

    /// 0…1: how visible the hand is (it fades in and out).
    private(set) var presence: Float = 0
    /// Seconds into the current loop.
    private(set) var time: Float = 0
    /// The hand snapped during the last `update` (sparks fly).
    private(set) var didSnap = false

    /// Advances the loop. `isShown`: every ingredient in orbit, nothing else in front of the player. The loop starts
    /// over each time the hand appears, so the player always sees it from the open hand.
    mutating func update(deltaTime: Float, isShown: Bool) {
        if isShown && presence == 0 { time = 0 }
        let step = deltaTime / Self.fadeDuration
        presence = isShown ? min(presence + step, 1) : max(presence - step, 0)
        let previous = time
        time = presence > 0 ? (time + deltaTime).truncatingRemainder(dividingBy: Self.period) : 0
        let wrapped = time < previous
        didSnap = presence > 0 && (wrapped
            ? previous < Self.snapTime || time >= Self.snapTime
            : previous < Self.snapTime && time >= Self.snapTime)
    }

    /// The hand now.
    var pose: Pose { Self.pose(at: time) }

    /// The flash of the snap, 0…1: up at once, dying out over 0.45 s.
    var flash: Float {
        let since = time - Self.snapTime
        return since >= 0 ? exp(-since / 0.15) : 0
    }

    // MARK: - Poses

    /// How far a finger bends at its first two joints (radians, towards the palm).
    struct FingerPose: Equatable {
        var base: Float
        var middle: Float
    }

    /// One key pose of the loop.
    struct KeyPose: Equatable {
        var index: FingerPose
        var middle: FingerPose
        var ring: FingerPose
        var little: FingerPose
        /// 0 = the thumb's metacarpal out to the side, 1 = turned towards the palm.
        var opposition: Float
        /// Where the thumb's tip goes.
        var thumb: ThumbTarget
    }

    enum ThumbTarget: Equatable {
        /// Relaxed, out to the side.
        case rest
        /// Pressed on the middle finger's pad.
        case middlePad
        /// Slid along the index, against its first phalanx.
        case alongIndex
    }

    static let open = KeyPose(index: FingerPose(base: 0.12, middle: 0.12), middle: FingerPose(base: 0.12, middle: 0.12),
                              ring: FingerPose(base: 0.18, middle: 0.2), little: FingerPose(base: 0.22, middle: 0.22),
                              opposition: 0, thumb: .rest)
    static let loaded = KeyPose(index: FingerPose(base: 0.25, middle: 0.35), middle: FingerPose(base: 1.0, middle: 0.85),
                                ring: FingerPose(base: 1.35, middle: 1.5), little: FingerPose(base: 1.4, middle: 1.5),
                                opposition: 1, thumb: .middlePad)
    static let snapped = KeyPose(index: FingerPose(base: 0.3, middle: 0.4), middle: FingerPose(base: 1.45, middle: 1.5),
                                 ring: FingerPose(base: 1.35, middle: 1.5), little: FingerPose(base: 1.4, middle: 1.5),
                                 opposition: 1, thumb: .alongIndex)

    /// The loop: (time, key pose); between two keys the hand eases from one to the other.
    static let keys: [(time: Float, pose: KeyPose)] = [
        (0, open), (0.2, open), (0.8, loaded), (1.18, loaded), (snapTime, snapped), (1.9, snapped),
        (2.6, open), (period, open)
    ]

    /// The hand at `time` seconds into the loop.
    static func pose(at time: Float) -> Pose {
        let time = min(max(time, 0), period)
        let next = keys.firstIndex { $0.time > time } ?? keys.count - 1
        let from = keys[max(next - 1, 0)]
        let to = keys[next]
        let span = to.time - from.time
        let progress = span > 0 ? Elixir.smootherstep((time - from.time) / span) : 1
        return pose(from.pose, to.pose, progress)
    }

    /// The hand between two key poses (`progress` 0…1, already eased).
    static func pose(_ from: KeyPose, _ to: KeyPose, _ progress: Float) -> Pose {
        func mix(_ first: FingerPose, _ second: FingerPose) -> FingerPose {
            FingerPose(base: simd_mix(first.base, second.base, progress),
                       middle: simd_mix(first.middle, second.middle, progress))
        }
        let fingers = [mix(from.index, to.index), mix(from.middle, to.middle), mix(from.ring, to.ring),
                       mix(from.little, to.little)]
        let chains = zip(Self.fingers, fingers).map { chain($0, pose: $1) }
        let opposition = simd_mix(from.opposition, to.opposition, progress)
        let start = target(from.thumb, fingers: zip(Self.fingers, [from.index, from.middle, from.ring, from.little])
            .map { chain($0, pose: $1) })
        let end = target(to.thumb, fingers: zip(Self.fingers, [to.index, to.middle, to.ring, to.little])
            .map { chain($0, pose: $1) })
        let thumb = thumbChain(opposition: opposition, target: simd_mix(start, end, SIMD3(repeating: progress)))
        let middle = chains[1]
        return Pose(thumb: thumb, middlePad: pad(of: middle, radius: Self.fingers[1].tipRadius), middleTip: middle[2],
                    fingers: chains)
    }

    // MARK: - The hand's shape

    struct Finger: Equatable {
        /// Its first joint, on the palm.
        var knuckle: SIMD3<Float>
        /// Leaning sideways (radians, + towards the little finger).
        var splay: Float
        var lengths: SIMD3<Float>
        /// At the knuckle; it tapers to the fingertip (`HandSurface.taper`).
        var radius: Float

        var tipRadius: Float { radius * HandSurface.taper.z }
    }

    /// Index, middle, ring and little finger.
    static let fingers = [
        Finger(knuckle: SIMD3(0.025, 0.092, 0), splay: -0.06, lengths: SIMD3(0.040, 0.024, 0.021), radius: 0.0085),
        Finger(knuckle: SIMD3(0.008, 0.096, 0), splay: 0, lengths: SIMD3(0.045, 0.028, 0.022), radius: 0.0088),
        Finger(knuckle: SIMD3(-0.009, 0.092, 0), splay: 0.06, lengths: SIMD3(0.042, 0.026, 0.021), radius: 0.0083),
        Finger(knuckle: SIMD3(-0.025, 0.083, 0), splay: 0.14, lengths: SIMD3(0.033, 0.020, 0.019), radius: 0.0075)
    ]
    /// Where the thumb starts (its metacarpal's root, at the base of the palm) and its bones' lengths.
    static let thumbBase = SIMD3<Float>(0.022, 0.02, 0.008)
    static let thumbLengths = SIMD3<Float>(0.044, 0.035, 0.031)
    static let thumbTipRadius: Float = 0.0092
    /// The thumb's metacarpal, out to the side and turned towards the palm.
    static let thumbSide = simd_normalize(SIMD3<Float>(0.75, 0.6, 0.25))
    static let thumbOpposed = simd_normalize(SIMD3<Float>(0.25, 0.65, 0.72))
    /// The relaxed thumb's tip.
    static let thumbRest = SIMD3<Float>(0.068, 0.088, 0.03)
    /// The side the thumb's middle joint bends out to (two-bone IK pole).
    static let thumbPole = simd_normalize(SIMD3<Float>(1, 0.1, -0.5))
    /// The three joints after the knuckle (the last one is the fingertip).
    static func chain(_ finger: Finger, pose: FingerPose) -> [SIMD3<Float>] {
        let angles = [pose.base, pose.base + pose.middle, pose.base + pose.middle + 0.7 * pose.middle]
        var point = finger.knuckle
        return (0..<3).map { bone in
            point += direction(splay: finger.splay, bend: angles[bone]) * finger.lengths[bone]
            return point
        }
    }

    /// A finger bone's direction: up, leaning sideways by `splay`, bent towards the palm by `bend`.
    static func direction(splay: Float, bend: Float) -> SIMD3<Float> {
        SIMD3(sin(splay) * cos(bend), cos(splay) * cos(bend), sin(bend))
    }

    /// The pad of a finger's last phalanx: `radius` off its axis, on its palm side, a little before the tip.
    static func pad(of joints: [SIMD3<Float>], radius: Float) -> SIMD3<Float> {
        let axis = simd_normalize(joints[2] - joints[1])
        let palmSide = simd_normalize(simd_cross(SIMD3(1, 0, 0), axis))
        return joints[2] - axis * 0.006 + palmSide * radius
    }

    private static func target(_ target: ThumbTarget, fingers: [[SIMD3<Float>]]) -> SIMD3<Float> {
        switch target {
        case .rest:
            return thumbRest
        case .middlePad:
            // The thumb's tip touching the pad: its centre one thumb radius further out.
            return pad(of: fingers[1], radius: Self.fingers[1].tipRadius + thumbTipRadius)
        case .alongIndex:
            // Against the index's first phalanx, on the palm's side.
            let index = fingers[0]
            let knuckle = Self.fingers[0].knuckle
            return (knuckle + index[0]) / 2 + SIMD3(0.004, 0, 0.02)
        }
    }

    /// The thumb's joints: its metacarpal (turned by `opposition`), then two phalanges reaching for `target`.
    static func thumbChain(opposition: Float, target: SIMD3<Float>) -> ThumbJoints {
        let metacarpal = simd_normalize(simd_mix(thumbSide, thumbOpposed, SIMD3(repeating: opposition)))
        let base = thumbBase + metacarpal * thumbLengths.x
        let reach = solve(from: base, to: target, lengths: SIMD2(thumbLengths.y, thumbLengths.z), pole: thumbPole)
        return ThumbJoints(base: base, joint: reach.joint, tip: reach.tip)
    }

    /// The thumb's joints after its root: the end of its metacarpal, its middle joint and its tip.
    struct ThumbJoints: Equatable {
        var base: SIMD3<Float>
        var joint: SIMD3<Float>
        var tip: SIMD3<Float>
    }

    /// Two-bone IK: the middle joint of a chain from `start` reaching for `target`, bending towards `pole`. Out of
    /// reach, the chain stretches straight towards it.
    static func solve(from start: SIMD3<Float>, to target: SIMD3<Float>, lengths: SIMD2<Float>,
                      pole: SIMD3<Float>) -> (joint: SIMD3<Float>, tip: SIMD3<Float>) {
        let offset = target - start
        let distance = min(max(simd_length(offset), abs(lengths.x - lengths.y) + 1e-4), lengths.x + lengths.y - 1e-5)
        let axis = simd_length(offset) > 1e-6 ? simd_normalize(offset) : SIMD3(0, 1, 0)
        let cosine = (lengths.x * lengths.x + distance * distance - lengths.y * lengths.y) / (2 * lengths.x * distance)
        let sine = (1 - min(cosine * cosine, 1)).squareRoot()
        var side = pole - axis * simd_dot(pole, axis)
        side = simd_length(side) > 1e-6 ? simd_normalize(side) : SIMD3(1, 0, 0)
        let joint = start + (axis * cosine + side * sine) * lengths.x
        let tip = joint + simd_normalize(start + axis * distance - joint) * lengths.y
        return (joint, tip)
    }
}
