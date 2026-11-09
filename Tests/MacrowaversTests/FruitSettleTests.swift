import RealityKit
import simd
import Testing
@testable import Macrowavers

/// A turned fruit eases back to face the player as it starts to open (`OrchardSystem.settleBeforeOpening`). It is
/// already in front of the player and as big: only its turn moves, and the easing must not count it as there before
/// its turn is, or it snaps.
@MainActor
struct FruitSettleTests {
    private let frame: Float = 1 / 90
    private let front = Transform(scale: SIMD3(repeating: 2))

    private func turnLeft(_ transform: Transform, to target: Transform) -> Float {
        2 * acos(min(abs(simd_dot(transform.rotation.vector, target.rotation.vector)), 1))
    }

    @Test func aTurnedFruitEasesBackInsteadOfSnapping() {
        var turned = front
        turned.rotation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 1, 0))
        let focus = FocusComponent(target: front, responsiveness: OrchardSystem.settleResponsiveness)

        let (next, isThere) = FocusSystem.step(turned, towards: focus, deltaTime: frame)

        #expect(!isThere, "a quarter turn away is not there yet")
        let left = turnLeft(next, to: front)
        #expect(left > 1.3 && left < .pi / 2, "one frame turns it a little: \(left) rad left")
    }

    @Test func itFacesThePlayerWithinAboutHalfASecond() {
        var transform = front
        transform.rotation = simd_quatf(angle: 2.5, axis: simd_normalize(SIMD3(1, 1, 0)))
        let focus = FocusComponent(target: front, responsiveness: OrchardSystem.settleResponsiveness)

        var frames = 0
        var isThere = false
        var leftAtAThird: Float?
        while !isThere && frames < 200 {
            (transform, isThere) = FocusSystem.step(transform, towards: focus, deltaTime: frame)
            frames += 1
            if frames == 30 { leftAtAThird = turnLeft(transform, to: front) }
        }

        #expect(isThere)
        #expect(Float(frames) * frame < 0.7, "there after \(Float(frames) * frame) s")
        #expect((leftAtAThird ?? .infinity) < 0.15, "a third of a second in: \(leftAtAThird ?? .infinity) rad left")
        #expect(transform == front, "it ends exactly facing the player")
    }

    /// Arriving from the tree it still settles as before: position, size and turn come in together.
    @Test func aFruitAlreadyFacingThePlayerIsThereAtOnce() {
        let focus = FocusComponent(target: front, responsiveness: OrchardSystem.settleResponsiveness)

        let (next, isThere) = FocusSystem.step(front, towards: focus, deltaTime: frame)

        #expect(isThere)
        #expect(next == front)
    }
}
