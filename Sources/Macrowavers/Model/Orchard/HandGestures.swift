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

    /// Thumb tip to middle tip: far apart right after a snap.
    var snapGap: Float { simd_distance(thumbTip, middleTip) }

    /// Thumb tip to the middle finger's last phalanx (the segment DIP → tip). Before a snap the thumb presses on
    /// the pad of that phalanx, not on its tip: the two tip joints can stay 2–4 cm apart while touching.
    var thumbToMiddlePad: Float {
        let segment = middleTip - middleDistal
        let length = simd_length_squared(segment)
        guard length > 1e-8 else { return simd_distance(thumbTip, middleTip) }
        let along = min(max(simd_dot(thumbTip - middleDistal, segment) / length, 0), 1)
        return simd_distance(thumbTip, middleDistal + segment * along)
    }

    /// Wrist to middle tip: shrinks when the middle finger flexes into the palm, grows when it stretches.
    var middleReach: Float { simd_distance(wrist, middleTip) }
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

/// The finger snap that brews the elixir: thumb pressed on the middle finger's pad, then, in a flash, the middle
/// finger slides off the thumb and flexes into the palm while the thumb flies away from it.
///
/// Hand tracking runs at 30–90 Hz and the snap itself takes a few hundredths of a second (the fast finger is
/// often reported a frame late, or estimated), so the detector does not follow the finger: it compares the two
/// poses on either side of the snap, each against the player's own hand, never against absolute hand sizes.
/// 1. **Loaded**: the thumb tip within `contactDistance` of the middle finger's last phalanx
///    (`thumbToMiddlePad`), and not pinching the index (thumb and index is the system's tap).
/// 2. **Released**, within `window` of the last loaded reading, compared with that reading:
///    - thumb and middle tips at least `separation` farther apart, opened at `minimumSpeed` or faster;
///    - the middle tip at least `curl` closer to the wrist (it flexed into the palm). Simply opening the fingers
///      stretches it instead, so it does not count.
/// Each hand has a `cooldown` after a snap.
struct SnapDetector {
    struct Settings {
        /// Thumb tip to the middle finger's last phalanx below this = loaded (m). Joint centres: a firm press
        /// reads 1–2 cm.
        var contactDistance: Float = 0.03
        /// Thumb tip to index tip above this while loaded (m): not a pinch.
        var pinchClearance: Float = 0.02
        /// Thumb and middle tips at least this much farther apart than when loaded (m); a snap opens ~4–7 cm.
        var separation: Float = 0.03
        /// The middle tip at least this much closer to the wrist than when loaded (m); a snap flexes it ~3–6 cm.
        var curl: Float = 0.012
        /// Longest time from the last loaded reading to the released one (s): a snap plus a late frame or two.
        var window: TimeInterval = 0.3
        /// The thumb–middle gap must open at least this fast (m/s); a snap opens it at 1 m/s or more.
        var minimumSpeed: Float = 0.5
        /// After a snap the same hand cannot snap again for this long (s).
        var cooldown: TimeInterval = 0.6
    }

    /// What the last released pose measured against its loaded pose (for tuning on the headset).
    struct Attempt: Equatable {
        var separation: Float
        var curl: Float
        var speed: Float
        var isSnap: Bool
    }

    private struct Loaded {
        var time: TimeInterval
        var gap: Float
        var reach: Float
    }

    private struct HandState {
        var loaded: Loaded?
        /// The latest reading was in the loaded pose.
        var isLoadedNow = false
        var lastTime: TimeInterval?
        var cooldownUntil: TimeInterval = 0
    }

    let settings: Settings
    private var hands: [HandSample.Chirality: HandState] = [:]
    /// The latest reading after a loaded pose (within `window`): how close it came to a snap.
    private(set) var lastAttempt: Attempt?
    /// Thumb to middle pad of the closest hand, at the latest readings (m).
    private(set) var closestContact: Float?

    init(settings: Settings = Settings()) {
        self.settings = settings
    }

    /// A hand holds the loaded pose right now: the label tells the player to snap.
    var isLoaded: Bool { hands.values.contains { $0.isLoadedNow } }

    /// Feeds one hand reading; returns true when this reading completes a snap.
    mutating func process(_ sample: HandSample) -> Bool {
        var state = hands[sample.chirality] ?? HandState()
        defer {
            hands[sample.chirality] = state
            closestContact = min(closestContact ?? .infinity, sample.thumbToMiddlePad)
        }
        // The same reading again (the frame is faster than the tracking), or an older one: nothing new.
        if let last = state.lastTime, sample.timestamp <= last { return false }
        state.lastTime = sample.timestamp

        let isPinching = simd_distance(sample.thumbTip, sample.indexTip) < settings.pinchClearance
        if sample.thumbToMiddlePad < settings.contactDistance && !isPinching {
            state.loaded = Loaded(time: sample.timestamp, gap: sample.snapGap, reach: sample.middleReach)
            state.isLoadedNow = true
            return false
        }
        state.isLoadedNow = false
        guard let loaded = state.loaded else { return false }
        let elapsed = sample.timestamp - loaded.time
        guard elapsed <= settings.window else {
            state.loaded = nil
            return false
        }
        let separation = sample.snapGap - loaded.gap
        let curl = loaded.reach - sample.middleReach
        let speed = separation / Float(max(elapsed, 1e-3))
        let isSnap = separation >= settings.separation && curl >= settings.curl && speed >= settings.minimumSpeed
            && sample.timestamp >= state.cooldownUntil
        lastAttempt = Attempt(separation: separation, curl: curl, speed: speed, isSnap: isSnap)
        guard isSnap else { return false }
        state.loaded = nil
        state.cooldownUntil = sample.timestamp + settings.cooldown
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
