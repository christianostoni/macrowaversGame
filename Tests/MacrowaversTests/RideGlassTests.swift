import simd
import Testing
@testable import Macrowavers

struct RideGlassTests {
    @Test func theLightStaysBehindTheMedallion() {
        for time in stride(from: Float(0), through: 120, by: 0.7) {
            let spot = RideGlass.lightSpot(time: time)
            #expect(simd_length(spot) <= RideGlass.orbit + RideGlass.sway + 1e-5)
            #expect(simd_length(spot) >= RideGlass.orbit - RideGlass.sway - 1e-5)
            // Inside the medallion (unit disc), its halo too at the farthest.
            #expect(simd_length(spot) < 1)
        }
    }

    @Test func theLightMovesOnAndGoesAllTheWayRound() {
        let quarter = RideGlass.period / 4
        let spots = (0..<4).map { RideGlass.lightSpot(time: Float($0) * quarter) }
        let angles = spots.map { atan2($0.y, $0.x) }
        for (first, second) in zip(angles, angles.dropFirst()) {
            var turn = second - first
            if turn < 0 { turn += 2 * .pi }
            #expect(abs(turn - .pi / 2) < 1e-3)
        }
    }

    @Test func theLaceTurnsItsArchOverTheShamseh() {
        for heading in [Float(0), 0.7, -2.1, 3.1] {
            let arch = RideGlass.turn(heading: heading).act(RideGlass.archDirection)
            let shamseh = simd_quatf(angle: heading, axis: SIMD3(0, 1, 0)).act(SIMD3(0, 0, -1))
            #expect(simd_distance(arch, shamseh) < 1e-4)
        }
        // Before the feast: straight ahead, where it will hang.
        #expect(simd_distance(RideGlass.turn(heading: nil).act(RideGlass.archDirection), SIMD3(0, 0, -1)) < 1e-4)
    }

    @Test func theLaceHangsBetweenTheShamsehAndThePaintedSky() {
        #expect(RideGlass.patternRadius > ShamsehSky.distance)
        #expect(RideGlass.patternRadius < DragonRideSystem.domeRadius)
    }
}
