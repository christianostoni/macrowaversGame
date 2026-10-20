import Foundation
import simd
import Testing
@testable import Macrowavers

/// A right hand with the middle knuckle at `knuckle`, its fingers stretched forwards (−Z).
private func hand(at time: TimeInterval, knuckle: SIMD3<Float> = SIMD3(0, 1, -0.4)) -> HandSample {
    HandSample(chirality: .right, timestamp: time, knuckle: knuckle, wrist: knuckle + SIMD3(0, 0, 0.09),
               thumbTip: knuckle + SIMD3(0.02, 0, -0.04), indexTip: knuckle + SIMD3(0.06, 0.02, -0.07),
               middleDistal: knuckle + SIMD3(0, 0, -0.065), middleTip: knuckle + SIMD3(0, 0, -0.085))
}

/// The poses of a finger snap, relative to the middle knuckle.
private enum SnapPose {
    /// Thumb pressed on the middle finger's pad, the finger half bent.
    case loaded
    /// Right after the snap: the middle finger flexed into the palm, the thumb away from it.
    case snapped
    /// The fingers simply opened again: the middle finger stretches, the thumb leaves it.
    case opened
}

private func snapHand(_ pose: SnapPose, at time: TimeInterval,
                      chirality: HandSample.Chirality = .right) -> HandSample {
    var sample = hand(at: time)
    sample.chirality = chirality
    let knuckle = sample.knuckle
    switch pose {
    case .loaded:
        sample.middleDistal = knuckle + SIMD3(0, -0.02, -0.06)
        sample.middleTip = knuckle + SIMD3(0.012, -0.035, -0.055)
        sample.thumbTip = knuckle + SIMD3(0.02, -0.03, -0.06)
    case .snapped:
        sample.middleDistal = knuckle + SIMD3(0, -0.035, -0.02)
        sample.middleTip = knuckle + SIMD3(0, -0.04, 0)
        sample.thumbTip = knuckle + SIMD3(0.04, 0.01, -0.06)
    case .opened:
        sample.thumbTip = knuckle + SIMD3(0.04, 0.01, -0.06)
    }
    return sample
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

struct SnapDetectorTests {
    /// Loaded at 0, then `pose` `after` seconds later.
    private func snap(_ pose: SnapPose = .snapped, after: TimeInterval, detector: inout SnapDetector) -> [Bool] {
        [detector.process(snapHand(.loaded, at: 0)), detector.process(snapHand(pose, at: after))]
    }

    @Test func thumbOffTheMiddleFingerIntoThePalmSnaps() {
        var detector = SnapDetector()
        // One reading apart at 90 Hz, or two at 30 Hz (a late frame): both the speed of a real snap.
        let fast = snap(after: 1.0 / 90, detector: &detector)
        #expect(fast == [false, true])
        var late = SnapDetector()
        let lateResult = snap(after: 2.0 / 30, detector: &late)
        #expect(lateResult == [false, true])
        #expect(late.lastAttempt?.isSnap == true)
    }

    @Test func thumbOnThePadLoadsEvenWithTheTipsApart() {
        // Pressing the pad, the two tip joints are ~2.8 cm apart: tip to tip alone would never see it loaded.
        var sample = snapHand(.loaded, at: 0)
        sample.middleTip = sample.middleDistal + SIMD3(0.03, 0, 0)
        // 1.2 cm off the pad, near the DIP joint.
        sample.thumbTip = sample.middleDistal + SIMD3(0.004, -0.012, 0)
        #expect(sample.snapGap > 0.025)
        #expect(sample.thumbToMiddlePad < SnapDetector.Settings().contactDistance)
        var detector = SnapDetector()
        _ = detector.process(sample)
        #expect(detector.isLoaded)
    }

    @Test func slowLateOrOpeningFingersDoNotSnap() {
        var slow = SnapDetector()
        let slowResult = snap(after: 0.25, detector: &slow)
        #expect(slowResult == [false, false])
        var late = SnapDetector()
        let lateResult = snap(after: 0.5, detector: &late)
        #expect(lateResult == [false, false])
        // Opening the fingers stretches the middle finger instead of flexing it.
        var open = SnapDetector()
        let openResult = snap(.opened, after: 1.0 / 90, detector: &open)
        #expect(openResult == [false, false])
        #expect(open.lastAttempt.map { !$0.isSnap && $0.curl < 0 } == true)
    }

    @Test func aPinchIsNotLoadingASnap() {
        var detector = SnapDetector()
        var pinch = snapHand(.loaded, at: 0)
        // Thumb on the index (the system's tap), the middle finger just as close.
        pinch.indexTip = pinch.thumbTip + SIMD3(0.005, 0, 0)
        let loaded = detector.process(pinch)
        let released = detector.process(snapHand(.snapped, at: 1.0 / 90))
        #expect(!loaded && !released && !detector.isLoaded)
    }

    @Test func repeatedReadingsAndCooldown() {
        var detector = SnapDetector()
        let first = snapHand(.loaded, at: 0)
        let second = snapHand(.snapped, at: 1.0 / 90)
        // Every reading arrives twice (the frame is faster than the tracking): one snap only.
        let fired = [detector.process(first), detector.process(first), detector.process(second), detector.process(second)]
        #expect(fired == [false, false, true, false])
        // A second snap right away is in the cooldown; later it counts.
        let again = [detector.process(snapHand(.loaded, at: 0.2)), detector.process(snapHand(.snapped, at: 0.21))]
        #expect(again == [false, false])
        let later = [detector.process(snapHand(.loaded, at: 1.0)), detector.process(snapHand(.snapped, at: 1.01))]
        #expect(later == [false, true])
    }

    @Test func eachHandSnapsOnItsOwnAndTheLabelSeesTheLoadedPose() {
        var detector = SnapDetector()
        let left = detector.process(snapHand(.loaded, at: 0, chirality: .left))
        #expect(detector.isLoaded)
        // The right hand only shows the snapped pose: no snap.
        let right = detector.process(snapHand(.snapped, at: 1.0 / 90, chirality: .right))
        #expect(!left && !right && detector.isLoaded)
        let leftSnap = detector.process(snapHand(.snapped, at: 2.0 / 90, chirality: .left))
        #expect(leftSnap && !detector.isLoaded)
    }
}

struct ElixirTests {
    @Test func takesThreeIngredientsThenIsReady() {
        var elixir = Elixir()
        let slots = [elixir.collect(), elixir.collect()]
        #expect(slots == [0, 1])
        let earlyBrew = elixir.brew()
        #expect(!earlyBrew)
        let lastSlot = elixir.collect()
        #expect(lastSlot == 2)
        #expect(elixir.state == .ready && elixir.isComplete)
        let extra = elixir.collect()
        #expect(extra == nil)
        let brews = [elixir.brew(), elixir.brew()]
        #expect(brews == [true, false])
    }

    @Test func fusesHoldsThenFlies() {
        var elixir = Elixir()
        for _ in 0..<Elixir.ingredientCount { _ = elixir.collect() }
        elixir.brew()
        elixir.update(deltaTime: Elixir.fusingDuration, canFly: true)
        #expect(elixir.state == .brewed)
        elixir.update(deltaTime: Elixir.brewedHold / 2, canFly: true)
        #expect(elixir.state == .brewed)
        elixir.update(deltaTime: Elixir.brewedHold, canFly: true)
        #expect(elixir.state == .flying)
        elixir.delivered()
        #expect(elixir.state == .delivered)
    }

    @Test func fusionCurvesHaveNoJumps() {
        var elixir = Elixir()
        #expect(elixir.displayScale == 0 && elixir.ingredientScale == 1)
        for _ in 0..<Elixir.ingredientCount { _ = elixir.collect() }
        elixir.brew()
        // The elixir grows out of the ingredients, with no jump when it is brewed.
        elixir.update(deltaTime: Elixir.fusingDuration * 0.999, canFly: true)
        let endOfFusion = elixir.displayScale
        elixir.update(deltaTime: Elixir.fusingDuration * 0.002, canFly: true)
        #expect(elixir.state == .brewed)
        #expect(abs(elixir.displayScale - endOfFusion) < 0.02)
        #expect(abs(elixir.ingredientScale - 0.3) < 1e-4)
        // It pops past its size, then settles at 1.
        elixir.update(deltaTime: Elixir.popDuration * 0.6, canFly: false)
        #expect(elixir.displayScale > 1)
        elixir.update(deltaTime: Elixir.popDuration, canFly: false)
        #expect(abs(elixir.displayScale - 1) < 1e-4)
        #expect(Elixir.smootherstep(0) == 0 && Elixir.smootherstep(1) == 1 && Elixir.smootherstep(0.5) == 0.5)
    }
}

struct ElixirOrbitTests {
    private let eyes = SIMD3<Float>(0, 1.6, 0)

    /// An orbit placed in front of eyes at 1.6 m, looking towards −Z.
    private func placedOrbit() -> ElixirOrbit {
        var orbit = ElixirOrbit()
        orbit.follow(eyes: eyes, forward: SIMD3(0, 0, -1), deltaTime: 0)
        return orbit
    }

    /// The orbit's points over a whole turn of every slot.
    private func wholeOrbit(_ orbit: ElixirOrbit) -> [SIMD3<Float>] {
        var orbit = orbit
        var points: [SIMD3<Float>] = []
        for _ in 0..<90 {
            points += (0..<3).map { orbit.point(slot: $0) }
            orbit.follow(eyes: eyes, forward: SIMD3(0, 0, -1), deltaTime: orbit.settings.period / 90)
        }
        return points
    }

    @Test func centreIsInFrontBelowTheEyesAndTheFarSideIsUp() {
        let orbit = placedOrbit()
        let settings = orbit.settings
        #expect(simd_distance(orbit.center, SIMD3(0, 1.6 - settings.drop, -settings.distance)) < 1e-5)
        // Slot 0 at phase 0: the far side, higher than the centre (the plane faces the eyes).
        let far = orbit.point(slot: 0, count: 1)
        #expect(abs(far.x) < 1e-5)
        #expect(far.z < orbit.center.z && far.y > orbit.center.y)
    }

    @Test func thePlayerSeesAllOfItClearOfTheirBody() {
        for point in wholeOrbit(placedOrbit()) {
            let offset = point - eyes
            let ahead = -offset.z
            // In front, never closer than 0.45 m: beyond the chest and the hands snapping in front of it.
            #expect(ahead >= 0.45)
            // Inside the comfortable field of view: within 25° to the sides, between 5° and 35° below the eyes.
            let side = atan2(abs(offset.x), ahead) * 180 / .pi
            let below = atan2(-offset.y, simd_length(SIMD2(offset.x, offset.z))) * 180 / .pi
            #expect(side <= 25)
            #expect(below >= 5 && below <= 35)
        }
    }

    @Test func turnsAtItsPeriod() {
        var orbit = placedOrbit()
        let start = orbit.point(slot: 0)
        for _ in 0..<Int(orbit.settings.period * 60) {
            orbit.follow(eyes: eyes, forward: SIMD3(0, 0, -1), deltaTime: 1.0 / 60)
        }
        #expect(simd_distance(orbit.point(slot: 0), start) < 0.01)
        // A quarter turn later the first slot is on the right.
        var quarter = placedOrbit()
        quarter.follow(eyes: eyes, forward: SIMD3(0, 0, -1), deltaTime: quarter.settings.period / 4)
        #expect(abs(quarter.point(slot: 0).x - quarter.settings.lateralRadius) < 1e-3)
    }

    @Test func followsTheBodyLazily() {
        var orbit = placedOrbit()
        // Glancing 20° to the side leaves the orbit where it is.
        let glance = simd_quatf(angle: 20 * .pi / 180, axis: SIMD3(0, 1, 0)).act(SIMD3<Float>(0, 0, -1))
        for _ in 0..<120 { orbit.follow(eyes: eyes, forward: glance, deltaTime: 1.0 / 60) }
        #expect(abs(orbit.yaw) < 1e-5)
        // Turning round (90°) brings it round in front again, smoothly.
        let turned = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 1, 0)).act(SIMD3<Float>(0, 0, -1))
        orbit.follow(eyes: eyes, forward: turned, deltaTime: 1.0 / 60)
        #expect(orbit.yaw > 0 && orbit.yaw < 0.1)
        for _ in 0..<300 { orbit.follow(eyes: eyes, forward: turned, deltaTime: 1.0 / 60) }
        #expect(abs(orbit.yaw - .pi / 2) < orbit.settings.turnSettled + 0.01)
        #expect(orbit.center.x < -orbit.settings.distance + 0.05)
        // Walking: it follows the eyes without jumping.
        orbit.follow(eyes: SIMD3(1, 1.6, 0), forward: turned, deltaTime: 1.0 / 60)
        #expect(orbit.eyes.x > 0 && orbit.eyes.x < 0.1)
    }

    @Test func risesAboveACloseFruitAndComesBack() {
        var orbit = placedOrbit()
        let resting = orbit.center.y
        for _ in 0..<120 { orbit.follow(eyes: eyes, forward: SIMD3(0, 0, -1), deltaTime: 1.0 / 60, makesRoom: true) }
        #expect(abs(orbit.center.y - resting - orbit.settings.roomLift) < 0.01)
        // The label stays down (it hides while a fruit is close anyway).
        #expect(orbit.hintPoint.y < resting)
        for _ in 0..<120 { orbit.follow(eyes: eyes, forward: SIMD3(0, 0, -1), deltaTime: 1.0 / 60) }
        #expect(abs(orbit.center.y - resting) < 0.01)
    }

    @Test func fusionSpiralsIntoTheCentre() {
        let orbit = placedOrbit()
        for slot in 0..<3 {
            #expect(simd_distance(orbit.fusionPosition(slot: slot, progress: 0), orbit.point(slot: slot)) < 1e-5)
            #expect(simd_distance(orbit.fusionPosition(slot: slot, progress: 1), orbit.center) < 1e-5)
        }
        let halfway = orbit.fusionPosition(slot: 1, progress: 0.5)
        #expect(simd_distance(halfway, orbit.center) < simd_distance(orbit.point(slot: 1), orbit.center))
    }
}

struct ElixirFlightTests {
    @Test func arcsAboveTheLineAndArrivesOnTime() {
        let start = SIMD3<Float>(0, 1.4, -0.6)
        let target = SIMD3<Float>(0.5, 1.2, -2.8)
        var flight = ElixirFlight(from: start, to: target)
        #expect(abs(flight.duration - simd_distance(start, target) / ElixirFlight.speed) < 1e-4)
        #expect(simd_distance(flight.position(towards: target), start) < 1e-5)
        flight.advance(deltaTime: flight.duration / 2)
        let middle = flight.position(towards: target)
        #expect(middle.y > (start.y + target.y) / 2 + 0.1)
        flight.advance(deltaTime: flight.duration)
        #expect(flight.isArrived)
        // The dragon moved meanwhile: the elixir still lands on it.
        let moved = target + SIMD3(0.3, 0.1, 0)
        #expect(simd_distance(flight.position(towards: moved), moved) < 1e-5)
        // Very close: it still takes a moment, never a jump.
        #expect(ElixirFlight(from: start, to: start + SIMD3(0, 0, -0.1)).duration == ElixirFlight.minimumDuration)
    }
}
