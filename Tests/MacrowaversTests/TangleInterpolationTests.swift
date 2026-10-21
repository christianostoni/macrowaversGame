import simd
import Testing
@testable import Macrowavers

/// The drawn body between two ticks of the 60 Hz simulation (the headset draws at 90 Hz).
struct TangleInterpolationTests {
    @Test func drawnBodyMovesOnEveryFrameAt90Hz() {
        let config = TangleConfig()
        let simulation = TangleSimulation(config: config, positions: TangleShape.trefoil.positions(config: config))
        let tail = config.nodeCount - 1
        #expect(simulation.grab(tail))
        simulation.drag(tail, to: simulation.positions[tail] + SIMD3(0, 0.05, 0))
        let frame: Float = 1.0 / 90.0
        // Until the first tick there is nothing to interpolate.
        simulation.step(deltaTime: frame)
        simulation.step(deltaTime: frame)

        var simulated = simulation.positions[tail]
        var drawn = simulation.interpolatedPositions[tail]
        var framesWithoutTick = 0
        for _ in 0..<30 {
            simulation.step(deltaTime: frame)
            if simulation.positions[tail] == simulated { framesWithoutTick += 1 }
            #expect(simulation.interpolatedPositions[tail] != drawn)
            simulated = simulation.positions[tail]
            drawn = simulation.interpolatedPositions[tail]
        }
        // The 60 Hz simulation skips one 90 Hz frame in three; what is drawn still moves on each of them.
        #expect(framesWithoutTick >= 9)
    }

    @Test func drawnBodyTurnsWithTheBody() {
        let config = TangleConfig()
        let simulation = TangleSimulation(config: config, positions: TangleShape.trefoil.positions(config: config))
        let tail = config.nodeCount - 1
        #expect(simulation.grab(tail))
        simulation.drag(tail, to: simulation.positions[tail] + SIMD3(0, 0.05, 0))
        // Between two ticks, with the body moving: the drawn body differs from the simulated one.
        for _ in 0..<4 { simulation.step(deltaTime: 1.0 / 90.0) }
        let center = simulation.centroid
        let angle: Float = 0.6
        let expected = simulation.interpolatedPositions.map { point in
            let offset = point - center
            return SIMD3(center.x + offset.x * cos(angle) - offset.z * sin(angle), point.y,
                         center.z + offset.x * sin(angle) + offset.z * cos(angle))
        }

        simulation.rotateBody(by: angle, around: center)

        for (drawn, rotated) in zip(simulation.interpolatedPositions, expected) {
            #expect(simd_distance(drawn, rotated) < 1e-5)
        }
    }
}
