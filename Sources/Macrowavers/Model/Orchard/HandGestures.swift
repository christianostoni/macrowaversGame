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
    /// Last joint of the middle finger before its tip (ARKit's `middleFingerIntermediateTip`, the DIP joint).
    var middleDistal: SIMD3<Float>
    var middleTip: SIMD3<Float>
    /// The other fingers' knuckles and tips, for the cupped hand that turns the fruit (`CupTurn`).
    var indexKnuckle = SIMD3<Float>.zero
    var ringKnuckle = SIMD3<Float>.zero
    var littleKnuckle = SIMD3<Float>.zero
    var ringTip = SIMD3<Float>.zero
    var littleTip = SIMD3<Float>.zero
    /// Last joint of the index finger before its tip (ARKit's `indexFingerIntermediateTip`). Nil: unknown, the index
    /// tip stands in for its last phalanx.
    var indexDistal: SIMD3<Float>?

    /// Middle of the palm: halfway from the wrist to the middle knuckle.
    var palmCentre: SIMD3<Float> { (wrist + knuckle) / 2 }

    /// Wrist to middle knuckle: the player's own hand size, which the snap's distances are measured against.
    var handLength: Float { simd_distance(wrist, knuckle) }

    /// Middle tip to the middle of the palm: it drops to about a third of `handLength` when the finger strikes the palm.
    var middleToPalm: Float { simd_distance(middleTip, palmCentre) }

    /// The palm's orientation, built from the joints alone: z from the wrist to the middle knuckle, x from the
    /// little knuckle to the index knuckle, y out of the palm's plane. Only its changes matter (how the hand turns),
    /// so its axes need not match ARKit's.
    var palmFrame: simd_quatf {
        let forward = simd_normalize(knuckle - wrist)
        let across = indexKnuckle - littleKnuckle
        let side = simd_normalize(across - simd_dot(across, forward) * forward)
        return simd_quatf(simd_float3x3(columns: (side, simd_cross(forward, side), forward)))
    }

    /// How far each finger (index, middle, ring, little) is bent, in degrees: the angle between the palm's
    /// direction (wrist to middle knuckle) and the finger's knuckle-to-tip line. About 0 stretched, 180 in a fist.
    var fingerBends: [Float] {
        let forward = simd_normalize(knuckle - wrist)
        return [(indexKnuckle, indexTip), (knuckle, middleTip), (ringKnuckle, ringTip), (littleKnuckle, littleTip)]
            .map { base, tip in
                let cosine = simd_dot(simd_normalize(tip - base), forward)
                return acos(min(max(cosine, -1), 1)) * 180 / .pi
            }
    }

    /// Thumb tip to middle tip: far apart right after a snap.
    var snapGap: Float { simd_distance(thumbTip, middleTip) }

    /// Thumb tip to the middle finger's last phalanx (the segment DIP → tip). Before a snap the thumb presses on
    /// the pad of that phalanx, not on its tip: the two tip joints can stay 2–4 cm apart while touching.
    var thumbToMiddlePad: Float { Self.distance(from: thumbTip, toSegment: middleDistal, middleTip) }

    /// Thumb tip to the index finger's last phalanx: a pinch presses there, the tip joints a couple of centimetres
    /// apart (without `indexDistal`, to the index tip).
    var thumbToIndexPad: Float {
        guard let indexDistal else { return simd_distance(thumbTip, indexTip) }
        return Self.distance(from: thumbTip, toSegment: indexDistal, indexTip)
    }

    private static func distance(from point: SIMD3<Float>, toSegment start: SIMD3<Float>,
                                 _ end: SIMD3<Float>) -> Float {
        let segment = end - start
        let length = simd_length_squared(segment)
        guard length > 1e-8 else { return simd_distance(point, end) }
        let along = min(max(simd_dot(point - start, segment) / length, 0), 1)
        return simd_distance(point, start + segment * along)
    }
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

/// The finger snap that brews the elixir and breathes the ride's fire, read the way a real snap moves:
/// 1. **Press**: the thumb tip pressed on the middle finger's last phalanx (`thumbToMiddlePad` under
///    `contactDistance`), nearer to it than to the index's, held at least `minimumPress` (the tension before the
///    flick). The thumb held on the index's pad as long (a pinch, the system's tap) unloads it. The press lasts until
///    the thumb is `releaseDistance` away (hysteresis: a jittery reading does not break it).
/// 2. **Strike**, within `releaseWindow` of the press's last firm reading, measured against the press (its firm reading
///    with the middle finger farthest from the palm, just before the flick) and the player's own hand (`handLength`),
///    never against the world, so moving the arm counts for nothing:
///    - the middle tip lands near the palm (`middleToPalm` at most `palmReach` hand lengths) after coming at least
///      `strike` hand lengths closer to it: a pinch that opens stretches the finger away from the palm instead;
///    - it came at `strikeSpeed` or faster (its fastest approach over any `speedSpan`): a slow fist is not a snap;
///    - the thumb and middle tips at least `separation` farther apart (the thumb is off the finger).
///
/// It fires on the first reading that completes the strike: no smoothing, no waiting for the hand to settle. It works
/// on timestamps, never on reading counts, so it behaves the same at 30 and 90 Hz, and feeding it every reading
/// (`HandTracker.recentSamples`) or only the latest each frame changes nothing but how finely it sees the strike.
/// Each hand on its own, with a `cooldown` after a snap.
struct SnapDetector {
    struct Settings {
        /// Thumb tip to the middle finger's last phalanx below this = pressed (m). Joint centres: a firm press reads
        /// 1–2 cm.
        var contactDistance: Float = 0.03
        /// A press lasts until the thumb is this far from that phalanx (m): above `contactDistance`, so tracking
        /// jitter around it neither breaks the press nor starts a release.
        var releaseDistance: Float = 0.04
        /// Shortest press that loads a snap (s): a snap holds the thumb on the finger for a tenth of a second or more;
        /// a thumb only sweeping past the middle finger (on its way to a pinch) touches it for a reading or two.
        var minimumPress: TimeInterval = 0.05
        /// Longest time from the press's last firm reading to the strike (s). The flick itself takes 50–100 ms;
        /// the rest is room for a late or estimated reading of the fast finger.
        var releaseWindow: TimeInterval = 0.25
        /// The middle tip ends at most this far from the middle of the palm, in hand lengths (`handLength`).
        /// Pressed it is about 1 away, struck on the palm about 0.3; a pinch opening moves it out to 1.2 or more.
        var palmReach: Float = 0.7
        /// The middle tip comes at least this much closer to the palm than it was pressed, in hand lengths
        /// (a snap: 0.6–0.7).
        var strike: Float = 0.2
        /// The middle tip's fastest approach to the palm must reach this (m/s). A snap: 1 m/s or more (7 cm in under
        /// a tenth of a second); curling the fingers slowly into a fist: a few tenths.
        var strikeSpeed: Float = 0.5
        /// Speeds are measured over at least this long (s): over one reading at 90 Hz (11 ms) a few millimetres of
        /// tracking jitter would read as a fast finger.
        var speedSpan: TimeInterval = 0.025
        /// The thumb and middle tips at least this much farther apart than pressed (m); a snap opens them 3–5 cm.
        var separation: Float = 0.025
        /// After a snap the same hand cannot snap again for this long (s).
        var cooldown: TimeInterval = 0.4
        /// When set, the wrist may move at most this far between the press and the strike (m): a snap moves the
        /// fingers, not the hand. On the ride the hands steer by moving: a quick turn of the horns that happens to
        /// curl a hand is not a snap.
        var maxWristTravel: Float?
    }

    /// What the latest reading after a press measured (for tuning on the headset).
    struct Attempt: Equatable {
        /// Thumb and middle tips, farther apart than pressed (m).
        var separation: Float
        /// How much closer to the palm the middle tip came, in hand lengths.
        var strike: Float
        /// The middle tip to the middle of the palm, in hand lengths.
        var palmReach: Float
        /// The middle tip's fastest approach to the palm since the press (m/s).
        var speed: Float
        var isSnap: Bool
    }

    /// One reading, as the snap needs it.
    private struct Point {
        var time: TimeInterval
        /// Middle tip to the middle of the palm (m).
        var toPalm: Float
        /// Thumb tip to middle tip (m).
        var gap: Float
        var wrist: SIMD3<Float>
        /// The thumb firmly on the middle finger's pad (under `contactDistance`, not on the index).
        var isFirm: Bool
        /// How fast the middle tip was coming to the palm (m/s, over at least `speedSpan`).
        var speed: Float
    }

    private struct HandState {
        /// When the current press began (nil: the thumb is off the middle finger).
        var pressStart: TimeInterval?
        /// The latest firm reading of a press held `minimumPress` (nil: nothing to snap from).
        var loadedUntil: TimeInterval?
        /// When the thumb came onto the index's pad (nil: it is not there).
        var indexPinchStart: TimeInterval?
        /// The readings of the last `releaseWindow` (and `speedSpan` before it), oldest first.
        var history: [Point] = []
        var lastTime: TimeInterval?
        var cooldownUntil: TimeInterval = 0
    }

    let settings: Settings
    private var hands: [HandSample.Chirality: HandState] = [:]
    /// The latest reading after a loaded press (within `releaseWindow`): how close it came to a snap.
    private(set) var lastAttempt: Attempt?
    /// Thumb to middle pad of the closest hand, at this frame's new readings (m).
    private(set) var closestContact: Float?

    init(settings: Settings = Settings()) {
        self.settings = settings
    }

    /// A hand presses its thumb on its middle finger right now: the hologram hand (`SnapHint`) brightens.
    var isLoaded: Bool { hands.values.contains { $0.pressStart != nil } }

    /// That hand presses its thumb on its middle finger right now (the ride stops reading it for steering).
    func isLoaded(_ chirality: HandSample.Chirality) -> Bool {
        hands[chirality]?.pressStart != nil
    }

    /// Feeds one hand reading; returns true when this reading completes a snap. Readings already seen (or older)
    /// are ignored, so the same reading may be fed again.
    mutating func process(_ sample: HandSample) -> Bool {
        var state = hands[sample.chirality] ?? HandState()
        defer { hands[sample.chirality] = state }
        if let last = state.lastTime, sample.timestamp <= last { return false }
        state.lastTime = sample.timestamp
        let pad = sample.thumbToMiddlePad
        closestContact = min(closestContact ?? .infinity, pad)

        // The thumb nearer to the index's pad than to the middle finger's: not a press.
        let isOnIndex = sample.thumbToIndexPad < pad
        let isFirm = pad < settings.contactDistance && !isOnIndex
        record(sample, isFirm: isFirm, in: &state)
        // Held there, it pinches the index (the system's tap): whatever was pressed before is not a snap. Only held:
        // in the flick the thumb often brushes the index's pad for a reading or two on its way up.
        if isOnIndex && sample.thumbToIndexPad < settings.contactDistance {
            let since = state.indexPinchStart ?? sample.timestamp
            state.indexPinchStart = since
            if sample.timestamp - since >= settings.minimumPress {
                state.pressStart = nil
                state.loadedUntil = nil
                return false
            }
        } else {
            state.indexPinchStart = nil
        }
        if isFirm {
            let start = state.pressStart ?? sample.timestamp
            state.pressStart = start
            if sample.timestamp - start >= settings.minimumPress { state.loadedUntil = sample.timestamp }
            return false
        }
        if pad >= settings.releaseDistance || isOnIndex { state.pressStart = nil }
        return strikes(sample, state: &state)
    }

    /// Adds the reading to the hand's history, with how fast its middle tip is coming to the palm.
    private func record(_ sample: HandSample, isFirm: Bool, in state: inout HandState) {
        let now = sample.timestamp
        let toPalm = sample.middleToPalm
        var speed: Float = 0
        if let reference = state.history.last(where: { now - $0.time >= settings.speedSpan }) ?? state.history.first {
            speed = (reference.toPalm - toPalm) / Float(max(now - reference.time, settings.speedSpan))
        }
        state.history.removeAll { now - $0.time > settings.releaseWindow + settings.speedSpan }
        state.history.append(Point(time: now, toPalm: toPalm, gap: sample.snapGap, wrist: sample.wrist,
                                   isFirm: isFirm, speed: speed))
    }

    /// A reading off the press: whether it completes the strike of a loaded press.
    private mutating func strikes(_ sample: HandSample, state: inout HandState) -> Bool {
        let now = sample.timestamp
        guard let loadedUntil = state.loadedUntil else { return false }
        guard now - loadedUntil <= settings.releaseWindow else {
            state.loadedUntil = nil
            return false
        }
        // Measured against the press before the flick: of its firm readings in the window, the one with the middle
        // finger farthest from the palm. Not simply the last: the thumb stays within `contactDistance` of the pad for
        // the flick's first readings, the finger already on its way.
        let firm = state.history.filter { $0.isFirm && now - $0.time <= settings.releaseWindow }
        guard let pressed = firm.max(by: { $0.toPalm < $1.toPalm }) else { return false }
        let speed = state.history.filter { $0.time > pressed.time }.map(\.speed).max() ?? 0
        let length = max(sample.handLength, 0.01)
        let toPalm = sample.middleToPalm
        var attempt = Attempt(separation: sample.snapGap - pressed.gap, strike: (pressed.toPalm - toPalm) / length,
                              palmReach: toPalm / length, speed: speed, isSnap: false)
        let isStill = settings.maxWristTravel.map { simd_distance(sample.wrist, pressed.wrist) <= $0 } ?? true
        let isStrike = attempt.palmReach <= settings.palmReach && attempt.strike >= settings.strike
            && attempt.speed >= settings.strikeSpeed && attempt.separation >= settings.separation && isStill
        attempt.isSnap = isStrike && now >= state.cooldownUntil
        lastAttempt = attempt
        guard isStrike else { return false }
        // A strike ends the press, even in the cooldown: it never fires late, once the cooldown is over.
        state.loadedUntil = nil
        state.pressStart = nil
        guard attempt.isSnap else { return false }
        state.cooldownUntil = now + settings.cooldown
        return true
    }

    /// Call once per frame before feeding the hands: `closestContact` then describes this frame's readings.
    mutating func beginFrame() {
        closestContact = nil
    }

    /// Forgets the hands.
    mutating func reset() {
        hands = [:]
        closestContact = nil
    }
}
