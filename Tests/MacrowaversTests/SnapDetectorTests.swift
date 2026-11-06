import Foundation
import simd
import Testing
@testable import Macrowavers

/// A synthetic right hand in its own space (m): wrist at the origin, fingers up (+Y), palm facing +Z, thumb towards
/// +X. Hand length (wrist to middle knuckle) 9.5 cm, the middle of the palm at (0, 0.0475, 0).
private struct Hand {
    var thumbTip: SIMD3<Float>
    var indexDistal: SIMD3<Float>
    var indexTip: SIMD3<Float>
    var middleDistal: SIMD3<Float>
    var middleTip: SIMD3<Float>
    var ringTip = SIMD3<Float>(-0.015, 0.06, 0.03)
    var littleTip = SIMD3<Float>(-0.03, 0.06, 0.03)

    static let indexKnuckle = SIMD3<Float>(0.025, 0.09, 0)
    static let middleKnuckle = SIMD3<Float>(0, 0.095, 0)
    static let ringKnuckle = SIMD3<Float>(-0.018, 0.09, 0)
    static let littleKnuckle = SIMD3<Float>(-0.034, 0.08, 0)

    /// Relaxed and open: the middle tip ~1.5 hand lengths from the palm.
    static let open = Hand(thumbTip: SIMD3(0.07, 0.075, 0.03), indexDistal: SIMD3(0.028, 0.158, 0.005),
                           indexTip: SIMD3(0.029, 0.18, 0.005), middleDistal: SIMD3(0, 0.165, 0.005),
                           middleTip: SIMD3(0, 0.188, 0.005), ringTip: SIMD3(-0.02, 0.178, 0.005),
                           littleTip: SIMD3(-0.038, 0.15, 0.005))
    /// The snap's press: the thumb ~1.3 cm off the middle finger's last phalanx, the index lifted clear, ring and
    /// little fingers curled. The middle tip ~1.05 hand lengths from the palm.
    static let pressed = Hand(thumbTip: SIMD3(0.018, 0.137, 0.062), indexDistal: SIMD3(0.03, 0.165, 0.02),
                              indexTip: SIMD3(0.033, 0.183, 0.028), middleDistal: SIMD3(0.005, 0.14, 0.045),
                              middleTip: SIMD3(0.01, 0.125, 0.062))
    /// Right after the snap: the middle tip on the palm by the ball of the thumb (~0.33 hand lengths from the
    /// palm's middle), the thumb up beside the index.
    static let struck = Hand(thumbTip: SIMD3(0.042, 0.125, 0.035), indexDistal: SIMD3(0.03, 0.163, 0.022),
                             indexTip: SIMD3(0.033, 0.18, 0.03), middleDistal: SIMD3(0.012, 0.078, 0.038),
                             middleTip: SIMD3(0.016, 0.056, 0.026))
    /// The system's tap: the thumb on the index's pad near its last joint (the two tip joints 2.1 cm apart), the
    /// middle finger right beside the index (the thumb 2.7 cm off its pad).
    static let indexPinch = Hand(thumbTip: SIMD3(0.035, 0.143, 0.042), indexDistal: SIMD3(0.028, 0.14, 0.035),
                                 indexTip: SIMD3(0.03, 0.124, 0.05), middleDistal: SIMD3(0.008, 0.142, 0.033),
                                 middleTip: SIMD3(0.01, 0.126, 0.048))
    /// A hand let go after a pinch: fingers loosely curled (the middle tip ~0.87 hand lengths from the palm), the
    /// thumb dropped away.
    static let relaxed = Hand(thumbTip: SIMD3(0.07, 0.08, 0.045), indexDistal: SIMD3(0.03, 0.15, 0.03),
                              indexTip: SIMD3(0.032, 0.135, 0.045), middleDistal: SIMD3(0.006, 0.13, 0.045),
                              middleTip: SIMD3(0.01, 0.105, 0.058))

    func mixed(with other: Hand, by amount: Float) -> Hand {
        func mix(_ first: SIMD3<Float>, _ second: SIMD3<Float>) -> SIMD3<Float> {
            first + (second - first) * amount
        }
        return Hand(thumbTip: mix(thumbTip, other.thumbTip), indexDistal: mix(indexDistal, other.indexDistal),
                    indexTip: mix(indexTip, other.indexTip), middleDistal: mix(middleDistal, other.middleDistal),
                    middleTip: mix(middleTip, other.middleTip), ringTip: mix(ringTip, other.ringTip),
                    littleTip: mix(littleTip, other.littleTip))
    }

    /// The same hand with the thumb `distance` off the middle finger's last phalanx, in the direction it is now.
    func withThumb(atPadDistance distance: Float) -> Hand {
        let segment = middleTip - middleDistal
        let along = min(max(simd_dot(thumbTip - middleDistal, segment) / simd_length_squared(segment), 0), 1)
        let pad = middleDistal + segment * along
        var hand = self
        hand.thumbTip = pad + simd_normalize(thumbTip - pad) * distance
        return hand
    }
}

/// Where the hand is in the scene: turned by `rotation`, then moved to `offset`.
private struct Placement {
    var rotation = simd_quatf(angle: 0.4, axis: SIMD3(0, 1, 0))
    var offset = SIMD3<Float>(0.15, 1.1, -0.35)
}

/// The hand at `pose` at `time`; between keys it moves at constant speed.
private typealias Key = (time: TimeInterval, pose: Hand)

/// The hand read like ARKit gives it, placed in the scene (a left hand is the mirror image).
private func sample(_ pose: Hand, at time: TimeInterval, chirality: HandSample.Chirality = .right,
                    placement: Placement = Placement()) -> HandSample {
    func place(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let mirrored = chirality == .left ? point * SIMD3(-1, 1, 1) : point
        return placement.rotation.act(mirrored) + placement.offset
    }
    return HandSample(chirality: chirality, timestamp: time, knuckle: place(Hand.middleKnuckle), wrist: place(.zero),
                      thumbTip: place(pose.thumbTip), indexTip: place(pose.indexTip),
                      middleDistal: place(pose.middleDistal), middleTip: place(pose.middleTip),
                      indexKnuckle: place(Hand.indexKnuckle), ringKnuckle: place(Hand.ringKnuckle),
                      littleKnuckle: place(Hand.littleKnuckle), ringTip: place(pose.ringTip),
                      littleTip: place(pose.littleTip), indexDistal: place(pose.indexDistal))
}

/// The readings of a hand moving through `keys`, at `rate` Hz from the first key to the last.
private func readings(_ keys: [Key], rate: Double = 90, chirality: HandSample.Chirality = .right,
                      placement: (TimeInterval) -> Placement = { _ in Placement() }) -> [HandSample] {
    guard let first = keys.first, let last = keys.last else { return [] }
    return (0...Int(((last.time - first.time) * rate).rounded())).map { step in
        let time = first.time + Double(step) / rate
        let next = keys.firstIndex { $0.time >= time } ?? keys.count - 1
        let pose: Hand
        if next == 0 {
            pose = keys[0].pose
        } else {
            let from = keys[next - 1]
            let to = keys[next]
            pose = from.pose.mixed(with: to.pose, by: Float((time - from.time) / (to.time - from.time)))
        }
        return sample(pose, at: time, chirality: chirality, placement: placement(time))
    }
}

/// When the detector fired over `samples`.
private func snaps(_ samples: [HandSample], detector: inout SnapDetector) -> [TimeInterval] {
    samples.compactMap { detector.process($0) ? $0.timestamp : nil }
}

/// A snap: the hand comes into the press, holds it until `release`, then the middle finger strikes the palm in `flick`.
private func snapKeys(release: TimeInterval = 0.5, flick: TimeInterval = 0.06,
                      pressed: Hand = .pressed) -> [Key] {
    [(0, .open), (0.2, pressed), (release, pressed), (release + flick, .struck), (release + 0.3, .struck)]
}

struct SnapDetectorTests {
    @Test func theTestHandsArePlausible() {
        let pressed = sample(.pressed, at: 0)
        let struck = sample(.struck, at: 0)
        #expect(abs(pressed.handLength - 0.095) < 1e-4)
        #expect(pressed.thumbToMiddlePad < 0.015 && pressed.thumbToIndexPad > 0.04)
        #expect(pressed.middleToPalm / pressed.handLength > 1)
        #expect(struck.middleToPalm / struck.handLength < 0.35 && struck.snapGap - pressed.snapGap > 0.05)
        // The tap that fooled the detector: thumb on the index's pad, tips over 2 cm apart, the middle finger's pad
        // under 3 cm away.
        let pinch = sample(.indexPinch, at: 0)
        #expect(simd_distance(pinch.thumbTip, pinch.indexTip) > 0.02)
        #expect(pinch.thumbToMiddlePad < SnapDetector.Settings().contactDistance)
        #expect(pinch.thumbToIndexPad < 0.011)
    }

    /// A real snap fires on the first reading where the middle finger is past halfway to the palm, before it lands:
    /// with a 60 ms flick, 33 ms after the release at 30, 60 and 90 Hz (at most one reading after the finger passes
    /// 0.7 hand lengths from the palm, ~30 ms in).
    @Test func aRealSnapFiresPromptlyAtAnyRate() {
        for rate in [30.0, 60, 90] {
            var detector = SnapDetector()
            let fired = snaps(readings(snapKeys(), rate: rate), detector: &detector)
            #expect(fired.count == 1, "\(rate) Hz: \(String(describing: detector.lastAttempt))")
            let latency = (fired.first ?? .infinity) - 0.5
            #expect(abs(latency - 0.0333) < 0.001, "\(rate) Hz: \(latency) s")
        }
    }

    /// A looser snap (a 0.1 s flick, like the hologram's) with the index resting right beside the middle finger.
    @Test func aLooserSnapWithTheIndexCloseStillFires() {
        var pressed = Hand.pressed
        pressed.indexDistal = SIMD3(0.028, 0.143, 0.043)
        pressed.indexTip = SIMD3(0.032, 0.128, 0.058)
        let reading = sample(pressed, at: 0)
        #expect(reading.thumbToIndexPad < 0.02 && reading.thumbToIndexPad > reading.thumbToMiddlePad)
        var detector = SnapDetector()
        let fired = snaps(readings(snapKeys(flick: 0.1, pressed: pressed)), detector: &detector)
        #expect(fired.count == 1, "\(String(describing: detector.lastAttempt))")
        // 56 ms after the release, before the finger lands at 100 ms.
        #expect((fired.first ?? .infinity) - 0.5 <= 0.06)
    }

    @Test func aThumbIndexPinchIsNotASnap() {
        // Tapped and let go into a relaxed hand, quickly or slowly, or opened wide: never pressed, never a snap.
        for end in [Hand.relaxed, .open] {
            for letGo in [0.06, 0.3] {
                var detector = SnapDetector()
                let samples = readings([(0, .open), (0.2, .indexPinch), (0.5, .indexPinch), (0.5 + letGo, end),
                                        (1.0, end)])
                var wasLoaded = false
                var fired: [TimeInterval] = []
                for reading in samples {
                    if detector.process(reading) { fired.append(reading.timestamp) }
                    if reading.timestamp >= 0.2 && reading.timestamp <= 0.5 { wasLoaded = wasLoaded || detector.isLoaded }
                }
                #expect(fired.isEmpty && !wasLoaded, "let go in \(letGo) s: \(String(describing: detector.lastAttempt))")
            }
        }
    }

    @Test func aThumbMiddlePinchThatOpensOrRelaxesIsNotASnap() {
        // Held a moment, then opened slowly, opened briskly, or let go into a relaxed hand.
        for (end, letGo) in [(Hand.open, 0.5), (.open, 0.08), (.relaxed, 0.06)] {
            var detector = SnapDetector()
            let samples = readings([(0, .open), (0.2, .pressed), (0.5, .pressed), (0.5 + letGo, end), (1.2, end)])
            let fired = snaps(samples, detector: &detector)
            #expect(fired.isEmpty, "let go in \(letGo) s: \(String(describing: detector.lastAttempt))")
            // It did read the press (the hologram brightens), and what it measured says why it was not a snap: the
            // middle finger never came near the palm.
            #expect(detector.lastAttempt.map { $0.palmReach > SnapDetector.Settings().palmReach } ?? false)
        }
    }

    @Test func curlingIntoAFistSlowlyIsNotASnap() {
        // From the press to the same end pose as a snap, but in 0.2 s (0.35 m/s) or 0.5 s.
        for flick in [0.2, 0.5] {
            var detector = SnapDetector()
            let fired = snaps(readings(snapKeys(flick: flick)), detector: &detector)
            #expect(fired.isEmpty, "\(flick) s: \(String(describing: detector.lastAttempt))")
        }
    }

    @Test func swingingTheArmWithAStillHandIsNotASnap() {
        // Between 0.3 and 0.45 s the whole hand turns 70° and moves 40 cm (~2.7 m/s), its fingers still.
        func swing(_ time: TimeInterval) -> Placement {
            let amount = Float(min(max((time - 0.3) / 0.15, 0), 1))
            return Placement(rotation: simd_quatf(angle: 0.4 + 1.2 * amount, axis: simd_normalize(SIMD3(0.3, 1, 0.2))),
                             offset: SIMD3(0.15 - 0.35 * amount, 1.1 + 0.2 * amount, -0.35))
        }
        for pose in [Hand.pressed, .open, .relaxed] {
            var detector = SnapDetector()
            let fired = snaps(readings([(0, pose), (0.8, pose)], placement: swing), detector: &detector)
            #expect(fired.isEmpty)
        }
        // The fingers are read against the hand: a snap made while the arm swings still counts (for the elixir; the
        // ride also wants the wrist still, `RideSnapTests`).
        var detector = SnapDetector()
        let moving = readings(snapKeys(release: 0.3, flick: 0.06), placement: swing)
        #expect(snaps(moving, detector: &detector).count == 1)
    }

    @Test func theThumbMustRestOnTheFingerBeforeTheFlick() {
        // The thumb brushes the middle finger on its way (under 50 ms in contact) and the finger flicks at once:
        // fingers waved about, not a snap.
        var detector = SnapDetector()
        let keys: [Key] = [(0, .open), (0.1, .pressed), (0.16, .struck), (0.5, .struck)]
        let contact = readings(keys).filter { $0.thumbToMiddlePad < SnapDetector.Settings().contactDistance }
        #expect(!contact.isEmpty && (contact.last?.timestamp ?? 0) - (contact.first?.timestamp ?? 0) < 0.05)
        #expect(snaps(readings(keys), detector: &detector).isEmpty)
    }

    @Test func trackingJitterAroundTheContactDoesNotBreakThePress() {
        // The thumb reads 2.5 / 3.5 cm off the pad in turn (the contact threshold is 3 cm): pressed throughout.
        let settings = SnapDetector.Settings()
        var detector = SnapDetector()
        for step in 0..<30 {
            let distance: Float = step.isMultiple(of: 2) ? 0.025 : 0.035
            #expect((distance < settings.contactDistance) == step.isMultiple(of: 2) && distance < settings.releaseDistance)
            let fired = detector.process(sample(Hand.pressed.withThumb(atPadDistance: distance), at: Double(step) / 90))
            #expect(!fired && detector.isLoaded)
        }
        // Past the release distance the press is over.
        _ = detector.process(sample(Hand.pressed.withThumb(atPadDistance: 0.045), at: 30.0 / 90))
        #expect(!detector.isLoaded)
    }

    @Test func thumbOnThePadPressesEvenWithTheTipsApart() {
        // Pressing the pad, the two tip joints are ~2.8 cm apart: tip to tip alone would never see it pressed.
        var pose = Hand.pressed
        pose.middleTip = pose.middleDistal + SIMD3(0.03, 0, 0)
        // 1.2 cm off the pad, near the DIP joint.
        pose.thumbTip = pose.middleDistal + SIMD3(0.004, -0.012, 0)
        let reading = sample(pose, at: 0)
        #expect(reading.snapGap > 0.025)
        #expect(reading.thumbToMiddlePad < SnapDetector.Settings().contactDistance)
        var detector = SnapDetector()
        _ = detector.process(reading)
        #expect(detector.isLoaded && detector.isLoaded(.right) && !detector.isLoaded(.left))
    }

    @Test func repeatedReadingsAndCooldown() {
        var detector = SnapDetector()
        // Every reading arrives twice (the frame reads the history again): one snap only, at 0.533 s.
        let first = readings([(0, .open), (0.2, .pressed), (0.5, .pressed), (0.56, .struck), (0.57, .struck)])
        #expect(snaps(first.flatMap { [$0, $0] }, detector: &detector) == [first[48].timestamp])
        // Pressed again at once and snapped 0.2 s later: in the cooldown, and it does not fire once that is over.
        let again = readings([(0.58, .struck), (0.62, .pressed), (0.7, .pressed), (0.76, .struck), (1.0, .struck)])
        #expect(snaps(again, detector: &detector).isEmpty)
        // Later it counts.
        let later = readings([(1.1, .open), (1.3, .pressed), (1.5, .pressed), (1.56, .struck), (1.8, .struck)])
        #expect(snaps(later, detector: &detector).count == 1)
    }

    @Test func eachHandSnapsOnItsOwn() {
        var detector = SnapDetector()
        // The left hand presses and holds; the right only shows the struck pose: no snap.
        let left = readings(snapKeys(), chirality: .left)
        let right = readings([(0, .struck), (0.8, .struck)], chirality: .right)
        var fired: [HandSample.Chirality] = []
        for (leftReading, rightReading) in zip(left, right) {
            if detector.process(rightReading) { fired.append(.right) }
            if detector.process(leftReading) { fired.append(.left) }
        }
        #expect(fired == [.left] && !detector.isLoaded)
    }
}
