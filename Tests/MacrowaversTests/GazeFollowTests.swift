import Foundation
import simd
import Testing
@testable import Macrowavers

/// The subtitles' place (`GazeFollow`): a little below the gaze, still while the player reads, gliding after a
/// bigger turn of the head and settling under the new gaze.
struct GazeFollowTests {
    private let ahead = SIMD3<Float>(0, 0, -1)

    private func angle(_ first: SIMD3<Float>, _ second: SIMD3<Float>) -> Float {
        acos(min(max(simd_dot(simd_normalize(first), simd_normalize(second)), -1), 1))
    }

    /// Looking `degrees` to the right of straight ahead.
    private func turned(_ degrees: Float) -> SIMD3<Float> {
        simd_quatf(angle: -degrees * .pi / 180, axis: SIMD3(0, 1, 0)).act(ahead)
    }

    @Test func theyFloatALittleBelowTheGaze() {
        for forward in [ahead, turned(60), simd_normalize(SIMD3<Float>(0.3, -0.4, -0.8))] {
            let target = GazeFollow.target(forward: forward)
            #expect(abs(angle(target, forward) - GazeFollow.drop) < 1e-4)
            #expect(target.y < forward.y)
        }
    }

    @Test func readingLeavesThemStill() {
        var follow = GazeFollow()
        let start = follow.update(forward: ahead, deltaTime: 1.0 / 90)
        var placed = start
        for _ in 0..<180 { placed = follow.update(forward: turned(8), deltaTime: 1.0 / 90) }
        #expect(placed == start)
    }

    @Test func aBiggerTurnBringsThemUnderTheNewGaze() {
        var follow = GazeFollow()
        _ = follow.update(forward: ahead, deltaTime: 1.0 / 90)
        let gaze = turned(30)
        var angles: [Float] = []
        for _ in 0..<270 { angles.append(angle(follow.update(forward: gaze, deltaTime: 1.0 / 90), GazeFollow.target(forward: gaze))) }
        // Gliding, never further, then settled under the new gaze.
        #expect(zip(angles, angles.dropFirst()).allSatisfy { $1 <= $0 + 1e-5 })
        #expect((angles.last ?? 1) < GazeFollow.settleAngle)
    }
}
