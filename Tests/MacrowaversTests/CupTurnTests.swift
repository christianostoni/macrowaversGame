import Foundation
import simd
import Testing
@testable import Macrowavers

/// A hand whose palm is turned by `turn`, wrist at `wrist`, every finger bent by `bend` degrees towards the palm.
private func cuppedHand(at time: TimeInterval, turn: simd_quatf = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)),
                        bend: Float = 70, wrist: SIMD3<Float> = SIMD3(0, 1, -0.4),
                        chirality: HandSample.Chirality = .right, pinching: Bool = false) -> HandSample {
    // Palm space: z from the wrist to the middle knuckle, x towards the index, the fingers bend towards −y.
    let angle = bend * .pi / 180
    let fingerDirection = SIMD3<Float>(0, -sin(angle), cos(angle))
    func world(_ point: SIMD3<Float>) -> SIMD3<Float> { wrist + turn.act(point) }
    let index = SIMD3<Float>(0.02, 0, 0.085)
    let middle = SIMD3<Float>(0, 0, 0.09)
    let ring = SIMD3<Float>(-0.02, 0, 0.085)
    let little = SIMD3<Float>(-0.038, 0, 0.075)
    let indexTip = index + 0.07 * fingerDirection
    let thumbTip = pinching ? indexTip : SIMD3(0.045, -0.03, 0.05)
    return HandSample(chirality: chirality, timestamp: time, knuckle: world(middle), wrist: world(.zero),
                      thumbTip: world(thumbTip), indexTip: world(indexTip),
                      middleDistal: world(middle + 0.06 * fingerDirection),
                      middleTip: world(middle + 0.08 * fingerDirection), indexKnuckle: world(index),
                      ringKnuckle: world(ring), littleKnuckle: world(little),
                      ringTip: world(ring + 0.075 * fingerDirection), littleTip: world(little + 0.06 * fingerDirection))
}

/// Just above the palm of an untuned `cuppedHand`.
private let fruitCentre = SIMD3<Float>(0, 1.08, -0.355)

private func angle(_ axis: SIMD3<Float>, _ degrees: Float) -> simd_quatf {
    simd_quatf(angle: degrees * .pi / 180, axis: axis)
}

/// Same rotation (q and −q included): they move two independent vectors to the same place.
private func same(_ lhs: simd_quatf, _ rhs: simd_quatf, tolerance: Float = 0.01) -> Bool {
    [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)].allSatisfy { simd_distance(lhs.act($0), rhs.act($0)) < tolerance }
}

struct CupTurnTests {
    /// Turns a cupped hand from 0 to `degrees` over 10 readings (30 Hz), then keeps it still for 15 readings.
    /// Returns every turn the fruit received, composed.
    private func turn(about axis: SIMD3<Float>, by degrees: Float, detector: inout CupTurn) -> simd_quatf {
        var total = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        for step in 0...25 {
            let progress = Float(min(step, 10)) / 10
            let sample = cuppedHand(at: Double(step) / 30, turn: angle(axis, degrees * progress))
            if let turn = detector.process([sample], fruitCentre: fruitCentre) { total = turn * total }
        }
        return total
    }

    @Test func theFruitTurnsWithACuppedHand() {
        var spin = CupTurn()
        #expect(same(turn(about: SIMD3(0, 1, 0), by: 30, detector: &spin), angle(SIMD3(0, 1, 0), 30)))
        #expect(spin.isHolding && spin.holdingHand == .right)
        var tilt = CupTurn()
        #expect(same(turn(about: SIMD3(1, 0, 0), by: -25, detector: &tilt), angle(SIMD3(1, 0, 0), -25)))
    }

    @Test func aFlatHandAFistAPinchOrAFarHandDoNotTurnIt() {
        let poses: [(TimeInterval, simd_quatf) -> HandSample] = [
            { cuppedHand(at: $0, turn: $1, bend: 5) },
            { cuppedHand(at: $0, turn: $1, bend: 160) },
            { cuppedHand(at: $0, turn: $1, pinching: true) },
            { cuppedHand(at: $0, turn: $1, wrist: SIMD3(0.3, 1, -0.4)) },
        ]
        for pose in poses {
            var detector = CupTurn()
            let turns = (0..<10).compactMap { step in
                detector.process([pose(Double(step) / 30, angle(SIMD3(0, 1, 0), Float(step) * 5))],
                                 fruitCentre: fruitCentre)
            }
            #expect(turns.isEmpty && !detector.isHolding)
        }
    }

    @Test func aWobblyOrBrieflyLostCupKeepsHoldingALongerOneLetsGo() {
        var detector = CupTurn()
        _ = detector.process([cuppedHand(at: 0, bend: 40)], fruitCentre: fruitCentre)
        // Bent a little less than needed to start: still inside the margin.
        let wobble = detector.process([cuppedHand(at: 1.0 / 30, turn: angle(SIMD3(0, 1, 0), 5), bend: 30)],
                                      fruitCentre: fruitCentre)
        #expect(wobble != nil && detector.isHolding)
        // One flat reading: held, without turning.
        let flat = detector.process([cuppedHand(at: 2.0 / 30, turn: angle(SIMD3(0, 1, 0), 10), bend: 5)],
                                    fruitCentre: fruitCentre)
        #expect(flat == nil && detector.isHolding)
        #expect(detector.process([cuppedHand(at: 3.0 / 30)], fruitCentre: fruitCentre) != nil)
        // Open for longer than the grace: it lets go.
        for step in 4...12 { _ = detector.process([cuppedHand(at: Double(step) / 30, bend: 5)], fruitCentre: fruitCentre) }
        #expect(!detector.isHolding)
    }

    @Test func aTrackingGapOrARepeatedReadingDoesNotMakeItJump() {
        var detector = CupTurn()
        _ = detector.process([cuppedHand(at: 0)], fruitCentre: fruitCentre)
        // The same reading again (the frame rate is higher than the tracking rate).
        #expect(detector.process([cuppedHand(at: 0)], fruitCentre: fruitCentre) == nil)
        // Half a second later, turned by 90°: no jump.
        let late = cuppedHand(at: 0.5, turn: angle(SIMD3(0, 1, 0), 90))
        #expect(detector.process([late], fruitCentre: fruitCentre) == nil && detector.isHolding)
        // From there it follows again.
        let next = detector.process([cuppedHand(at: 0.5 + 1.0 / 30, turn: angle(SIMD3(0, 1, 0), 92))],
                                    fruitCentre: fruitCentre)
        #expect(next.map { $0.angle < 0.05 } == true)
    }

    @Test func oneHandAtATime() {
        var detector = CupTurn()
        let both = [cuppedHand(at: 0, chirality: .right), cuppedHand(at: 0, chirality: .left)]
        _ = detector.process(both, fruitCentre: fruitCentre)
        let holder = detector.holdingHand
        #expect(holder != nil)
        let other: HandSample.Chirality = holder == .left ? .right : .left
        // Only the other hand turns: nothing happens.
        let turned = [cuppedHand(at: 1.0 / 30, chirality: holder ?? .right),
                      cuppedHand(at: 1.0 / 30, turn: angle(SIMD3(0, 1, 0), 20), chirality: other)]
        #expect(detector.process(turned, fruitCentre: fruitCentre).map { $0.angle < 0.01 } == true)
        // The holding hand leaves: the other one can take over.
        _ = detector.process([cuppedHand(at: 2.0 / 30, chirality: other)], fruitCentre: fruitCentre)
        #expect(!detector.isHolding)
        _ = detector.process([cuppedHand(at: 3.0 / 30, chirality: other)], fruitCentre: fruitCentre)
        #expect(detector.holdingHand == other)
    }

    @Test func thePalmFrameAndTheBendsFollowTheJoints() {
        let turn = angle(simd_normalize(SIMD3(1, 2, -0.5)), 75)
        let hand = cuppedHand(at: 0, turn: turn, bend: 50)
        #expect(same(hand.palmFrame, turn, tolerance: 1e-4))
        #expect(hand.fingerBends.allSatisfy { abs($0 - 50) < 6 })
    }
}
