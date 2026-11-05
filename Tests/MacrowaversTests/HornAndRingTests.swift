import simd
import Testing
@testable import Macrowavers

struct HornTipsTests {
    @Test func findsTheTopOfEachHorn() throws {
        // Two horns rising from the head, the right one a little lower and shorter (like the stone dragon's).
        var points: [SIMD3<Float>] = []
        for step in 0...10 {
            let along = Float(step) / 10
            points.append(SIMD3(-0.03 - 0.06 * along, 0.12 * along, -0.07 * along))
            points.append(SIMD3(0.03 + 0.015 * along, 0.115 * along, -0.1 * along))
        }
        let tips = try #require(HornTips.find(in: points))
        #expect(simd_distance(tips.left, SIMD3(-0.09, 0.12, -0.07)) < 1e-5)
        #expect(simd_distance(tips.right, SIMD3(0.045, 0.115, -0.1)) < 1e-5)
    }

    @Test func picksTheOuterHalfOfEachHorn() throws {
        // Two straight horns, a triangle every tenth of their length.
        var positions: [SIMD3<Float>] = [], indices: [UInt32] = []
        for side: Float in [-1, 1] {
            for step in 0..<10 {
                let (low, high) = (Float(step) / 10, Float(step + 1) / 10)
                let first = UInt32(positions.count)
                positions += [SIMD3(side * (0.03 + 0.05 * low), 0.12 * low, 0),
                              SIMD3(side * (0.03 + 0.05 * high), 0.12 * high, 0),
                              SIMD3(side * (0.03 + 0.05 * high), 0.12 * high, 0.005)]
                indices += [first, first + 1, first + 2]
            }
        }
        let outer = try #require(HornTips.triangles(positions: positions, indices: indices, base: 0, along: 0.5...1.5))
        // Five of ten on each horn: those whose middle is past half way.
        #expect(outer.count == 2 * 5 * 3)
        #expect(outer.allSatisfy { positions[Int($0)].y >= 0.06 - 1e-5 })
    }

    @Test func tellsWhichWayTheNormalsPoint() {
        // Two little boxes' corners as horns, normals out from each box's middle.
        var positions: [SIMD3<Float>] = []
        for side: Float in [-1, 1] {
            for corner in 0..<8 {
                let offset = SIMD3<Float>(corner & 1 == 0 ? -1 : 1, corner & 2 == 0 ? -1 : 1, corner & 4 == 0 ? -1 : 1)
                positions.append(SIMD3(side * 0.1, 0.05 + 0.01 * Float(corner), 0) + offset * 0.01)
            }
        }
        let centres = [SIMD3<Float>(-0.1, 0.085, 0), SIMD3(0.1, 0.085, 0)]
        let out = positions.enumerated().map { simd_normalize($1 - centres[$0 / 8]) }
        #expect(HornTips.outward(positions: positions, normals: out) == 1)
        #expect(HornTips.outward(positions: positions, normals: out.map { -$0 }) == -1)
    }

    @Test func needsTwoHorns() {
        #expect(HornTips.find(in: []) == nil)
        #expect(HornTips.find(in: [SIMD3(0, 1, 0), SIMD3(0, 0.5, 0)]) == nil)
    }
}

struct RingTurnTests {
    @Test func turnsWithThePinch() {
        let start = RingTurn.angle(of: SIMD3(0, 0, 1))
        let end = RingTurn.angle(of: SIMD3(1, 0, 0))
        let turn = RingTurn.turn(from: start, to: end)
        // A quarter turn about +Y takes the ring's +Z to its +X: the fruit follows the hand.
        #expect(abs(turn - .pi / 2) < 1e-5)
        let moved = simd_quatf(angle: turn, axis: SIMD3(0, 1, 0)).act(SIMD3(0, 0, 1))
        #expect(simd_distance(moved, SIMD3(1, 0, 0)) < 1e-5)
    }

    @Test func crossesTheSeamTheShortWay() {
        #expect(abs(RingTurn.turn(from: 3.1, to: -3.1) - (2 * .pi - 6.2)) < 1e-4)
        #expect(abs(RingTurn.turn(from: -3.1, to: 3.1) + (2 * .pi - 6.2)) < 1e-4)
    }

    @Test func sitsJustUnderTheFruit() {
        let (centre, radius) = RingTurn.placement(min: SIMD3(-0.1, -0.08, -0.05), max: SIMD3(0.1, 0.12, 0.05))
        #expect(simd_distance(centre, SIMD3(0, -0.092, 0)) < 1e-5)
        #expect(abs(radius - (0.1 * 0.85 + 0.015)) < 1e-5)
    }
}
