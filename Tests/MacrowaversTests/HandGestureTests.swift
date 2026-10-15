import Foundation
import simd
import Testing
@testable import Macrowavers

/// A right hand at `knuckle`, palm normal turned by `roll` around the hand's axis (−Z), pinching or not.
private func hand(at time: TimeInterval, knuckle: SIMD3<Float> = SIMD3(0, 1, -0.4), roll: Float = 0,
                  pinching: Bool = true) -> HandSample {
    let wrist = knuckle + SIMD3(0, 0, 0.09)
    let thumbTip = knuckle + SIMD3(0.02, 0, -0.04)
    let indexTip = thumbTip + SIMD3(pinching ? 0.01 : 0.06, 0, 0)
    let normal = simd_quatf(angle: roll, axis: SIMD3(0, 0, -1)).act(SIMD3(0, -1, 0))
    return HandSample(chirality: .right, timestamp: time, knuckle: knuckle, wrist: wrist,
                      thumbTip: thumbTip, indexTip: indexTip, palmNormal: normal)
}

struct ChopDetectorTests {
    private let target = ChopDetector.Target(center: SIMD3(0, 1, -0.4), baseY: 0.92, radius: 0.1, heightWindow: 0.3)

    /// Feeds the knuckle heights (at `x`, 30 Hz unless `interval` says otherwise); returns which readings chopped.
    private func chops(_ heights: [Float], x: Float = 0, interval: TimeInterval = 1.0 / 30,
                       detector: inout ChopDetector) -> [Bool] {
        heights.enumerated().map { index, height in
            detector.process(hand(at: Double(index) * interval, knuckle: SIMD3(x, height, -0.4)), target: target)
        }
    }

    @Test func fastHandThroughTheFruitChops() {
        var detector = ChopDetector()
        // 2.4 m/s down, over the fruit.
        let result = chops([1.1, 1.02], detector: &detector)
        #expect(result == [false, true])
    }

    @Test func slowBesideOrInterruptedHandsDoNotChop() {
        var slow = ChopDetector()
        let slowResult = chops([1.1, 1.05], interval: 0.1, detector: &slow)
        #expect(slowResult == [false, false])
        var beside = ChopDetector()
        let besideResult = chops([1.1, 1.02], x: 0.3, detector: &beside)
        #expect(besideResult == [false, false])
        // A tracking gap is not a movement.
        var gap = ChopDetector()
        let gapResult = chops([1.2, 1.0], interval: 0.5, detector: &gap)
        #expect(gapResult == [false, false])
    }

    @Test func cooldownAfterAChop() {
        var detector = ChopDetector()
        let result = chops([1.1, 1.02, 1.1, 1.02], detector: &detector)
        #expect(result == [false, true, false, false])
    }
}

struct TwistDetectorTests {
    /// Feeds a twist of `degrees` over `duration` seconds at 90 Hz; returns whether it fired.
    private func twist(degrees: Float, duration: TimeInterval, pinching: Bool = true, isLooking: Bool = true) -> Bool {
        var detector = TwistDetector()
        let steps = Int(duration * 90)
        var fired = false
        for step in 0...steps {
            let progress = Float(step) / Float(steps)
            let sample = hand(at: Double(step) / 90, roll: progress * degrees * .pi / 180, pinching: pinching)
            fired = detector.process(sample, isLooking: isLooking) || fired
        }
        return fired
    }

    @Test func pinchedTwistWhileLookingFires() {
        #expect(twist(degrees: 80, duration: 0.6))
        #expect(twist(degrees: -80, duration: 0.6))
    }

    @Test func smallSlowUnpinchedOrLookingAwayDoesNot() {
        #expect(!twist(degrees: 30, duration: 0.6))
        #expect(!twist(degrees: 80, duration: 3))
        #expect(!twist(degrees: 80, duration: 0.6, pinching: false))
        #expect(!twist(degrees: 80, duration: 0.6, isLooking: false))
    }

    @Test func progressShowsHowFarTheTwistIs() {
        var detector = TwistDetector()
        for step in 0...30 {
            let sample = hand(at: Double(step) / 90, roll: Float(step) / 30 * 30 * .pi / 180)
            _ = detector.process(sample, isLooking: true)
        }
        // 30° of the 45° needed.
        #expect(abs(detector.progress - 30.0 / 45.0) < 0.05)
        // Letting go of the pinch starts over.
        _ = detector.process(hand(at: 31.0 / 90, pinching: false), isLooking: true)
        #expect(detector.progress == 0)
    }

    @Test func repeatedReadingDoesNotRestartTheTwist() {
        var detector = TwistDetector()
        var fired = false
        for step in 0...54 {
            let sample = hand(at: Double(step) / 90, roll: Float(step) / 54 * 80 * .pi / 180)
            // Every reading arrives twice (the frame is faster than the tracking).
            fired = detector.process(sample, isLooking: true) || fired
            fired = detector.process(sample, isLooking: true) || fired
        }
        #expect(fired)
    }

    @Test func rollIgnoresBendingTheWrist() {
        let axis = SIMD3<Float>(0, 0, -1)
        let palm = SIMD3<Float>(0, -1, 0)
        // Tilting the palm along the hand's axis is not a roll.
        let bent = simd_normalize(SIMD3<Float>(0, -1, -0.5))
        #expect(abs(TwistDetector.roll(from: palm, to: bent, around: axis)) < 1e-4)
        let rolled = simd_quatf(angle: 0.5, axis: axis).act(palm)
        #expect(abs(TwistDetector.roll(from: palm, to: rolled, around: axis) - 0.5) < 1e-4)
    }

    @Test func lookingAtTheKalash() {
        let eyes = SIMD3<Float>(0, 1.6, 0)
        let kalash = SIMD3<Float>(0.25, 1.0, -0.15)
        #expect(TwistDetector.isLooking(from: eyes, forward: simd_normalize(kalash - eyes), at: kalash))
        #expect(!TwistDetector.isLooking(from: eyes, forward: SIMD3(0, 0, -1), at: kalash))
    }
}

struct KalashTests {
    @Test func fillsThreeSlotsThenIsReady() {
        var kalash = Kalash()
        let slots = [kalash.store(), kalash.store()]
        #expect(slots == [0, 1])
        let earlyCast = kalash.cast()
        #expect(!earlyCast)
        let lastSlot = kalash.store()
        #expect(lastSlot == 2)
        #expect(kalash.spell == .ready)
        let extra = kalash.store()
        #expect(extra == nil)
        let casts = [kalash.cast(), kalash.cast()]
        #expect(casts == [true, false])
    }

    @Test func spellFormsHoldsThenFlies() {
        var kalash = Kalash()
        for _ in 0..<Kalash.capacity { _ = kalash.store() }
        kalash.cast()
        kalash.update(deltaTime: Kalash.formingDuration, canFly: true)
        #expect(kalash.spell == .formed)
        kalash.update(deltaTime: Kalash.formedHold / 2, canFly: true)
        #expect(kalash.spell == .formed)
        kalash.update(deltaTime: Kalash.formedHold, canFly: true)
        #expect(kalash.spell == .flying)
        kalash.delivered()
        #expect(kalash.spell == .delivered)
    }
}
