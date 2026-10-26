import simd
import Testing
@testable import Macrowavers

struct DragonRideTests {
    /// Flies `seconds` with the hands held still where given (ride space).
    private func fly(_ ride: inout DragonRide, seconds: Float, left: SIMD3<Float>?, right: SIMD3<Float>?,
                     tracked: Bool = true) {
        for _ in 0..<Int(seconds * 60) {
            ride.holdHorns(left: left, right: right)
            ride.update(deltaTime: 1.0 / 60.0, left: left, right: right, isHandTrackingAvailable: tracked)
        }
    }

    /// A ride past its dark arrival, the hands resting on the horns at `rest`.
    private func riding(rest: SIMD3<Float>) -> DragonRide {
        var ride = DragonRide()
        fly(&ride, seconds: DragonRide.Settings.arrivalDuration + 0.1, left: nil, right: nil)
        fly(&ride, seconds: 0.1, left: rest + SIMD3(-0.2, 0, 0), right: rest + SIMD3(0.2, 0, 0))
        return ride
    }

    private let rest = SIMD3<Float>(0, -0.3, -0.35)

    @Test func theStoryEndsOnTheDragonsBackInFullImmersion() {
        #expect(StoryStep.allCases.filter(\.isFullyImmersed) == [.ride, .secondChapter, .feast])
        #expect(StoryStep.ride.page == nil && StoryStep.ride.revealsWorld)
        let focus = SceneFocus(isFruitFocused: false, isElixirFlying: false, phase: .free, isDragonSpeaking: false,
                               isRiding: true)
        #expect(focus == .ride)
        // The room's island and dragon are gone.
        #expect(focus.opacity(of: .island) == 0 && focus.opacity(of: .dragon) == 0)
    }

    @Test func handsStillOnTheHornsFlyStraightAndLevel() {
        var ride = riding(rest: rest)
        #expect(ride.rest != nil)
        let start = ride.position
        fly(&ride, seconds: 3, left: rest + SIMD3(-0.2, 0, 0), right: rest + SIMD3(0.2, 0, 0))
        #expect(abs(ride.yaw) < 1e-3 && abs(ride.pitch) < 1e-3)
        let travelled = ride.position - start
        // Straight ahead (-Z) at cruising speed.
        #expect(abs(travelled.x) < 1e-3 && abs(travelled.y) < 1e-3)
        #expect(abs(-travelled.z - 3 * DragonRide.Settings.cruiseSpeed) < 0.3)
    }

    @Test func theLowerHandTurnsTowardsItsSide() {
        var right = riding(rest: rest)
        fly(&right, seconds: 2, left: rest + SIMD3(-0.2, 0.12, 0), right: rest + SIMD3(0.2, -0.12, 0))
        // Turning right: heading clockwise from above, flying towards +X, the dragon leaning right.
        #expect(right.yaw < -0.2 && right.forward.x > 0.2 && right.bank > 0.1)

        var left = riding(rest: rest)
        fly(&left, seconds: 2, left: rest + SIMD3(-0.2, -0.12, 0), right: rest + SIMD3(0.2, 0.12, 0))
        #expect(left.yaw > 0.2 && left.forward.x < -0.2 && left.bank < -0.1)
    }

    @Test func bothHandsUpClimbDownDiveForwardSpeedsUp() {
        var climb = riding(rest: rest)
        fly(&climb, seconds: 2, left: rest + SIMD3(-0.2, 0.2, 0), right: rest + SIMD3(0.2, 0.2, 0))
        #expect(climb.pitch > 0.2 && climb.position.y > 0.5)

        var dive = riding(rest: rest)
        fly(&dive, seconds: 2, left: rest + SIMD3(-0.2, -0.2, 0), right: rest + SIMD3(0.2, -0.2, 0))
        #expect(dive.pitch < -0.2 && dive.position.y < -0.5)

        var boost = riding(rest: rest)
        fly(&boost, seconds: 3, left: rest + SIMD3(-0.2, 0, -0.2), right: rest + SIMD3(0.2, 0, -0.2))
        #expect(boost.speed > DragonRide.Settings.boostSpeed - 0.5)
    }

    @Test func letGoTheDragonLevelsOutAndNothingSteersDuringTheArrival() {
        var ride = riding(rest: rest)
        fly(&ride, seconds: 2, left: rest + SIMD3(-0.2, 0.2, 0), right: rest + SIMD3(0.2, 0.2, 0))
        fly(&ride, seconds: 4, left: nil, right: rest)
        #expect(abs(ride.pitch) < 0.01 && abs(ride.turnRate) < 0.01)

        // Hands up during the dark arrival: nothing happens yet, and they don't count as the rest position.
        var arriving = DragonRide()
        fly(&arriving, seconds: 2, left: SIMD3(-0.2, 0.3, -0.3), right: SIMD3(0.2, -0.3, -0.3))
        #expect(arriving.isArriving && arriving.rest == nil && arriving.yaw == 0 && arriving.pitch == 0)
    }

    @Test func withoutHandTrackingTheAutopilotFlies() {
        var ride = DragonRide()
        fly(&ride, seconds: DragonRide.Settings.arrivalDuration + 6, left: nil, right: nil, tracked: false)
        #expect(abs(ride.yaw) > 0.05)
    }

    @Test func theDragonIsUnderThePlayerHeadAheadTailBehind() {
        var ride = riding(rest: rest)
        let config = TangleConfig()
        let spacing = config.segmentLength * 2.6
        let body = ride.body(count: config.nodeCount, spacing: spacing, seat: 1.4, seatHeight: 0.55)
        #expect(body.count == config.nodeCount)
        #expect(body[0].z < -1.3 && body[body.count - 1].z > 3)
        // Right under the player: below the eyes, centred.
        let seatIndex = Int((1.4 / spacing).rounded())
        #expect(abs(body[seatIndex].x) < 0.05 && abs(body[seatIndex].y + 0.55) < 0.05)

        // In a right turn the body bends into it: head and tail both towards +X.
        fly(&ride, seconds: 2, left: rest + SIMD3(-0.2, 0.12, 0), right: rest + SIMD3(0.2, -0.12, 0))
        let turning = ride.body(count: config.nodeCount, spacing: spacing, seat: 1.4, seatHeight: 0.55)
        #expect(turning[0].x > 0.05 && turning[turning.count - 1].x > 0.3)
    }

    @Test func theSkySeenFromTheSeatMovesTowardsThePlayer() {
        var ride = riding(rest: rest)
        let speck = ride.position + ride.forward * 10
        let before = ride.rideFromSky(speck)
        fly(&ride, seconds: 1, left: rest + SIMD3(-0.2, 0, 0), right: rest + SIMD3(0.2, 0, 0))
        let after = ride.rideFromSky(speck)
        // Straight ahead, and closer.
        #expect(before.z < -9.9 && after.z > before.z + 2)
        #expect(abs(after.x) < 1e-3)
    }
}
