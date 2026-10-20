import simd
import Testing
@testable import Macrowavers

struct TimeOfDayTests {
    @Test func gatheringTheIngredientsIsTheMorning() {
        let clocks = (0...3).map { TimeOfDay.target(phase: .captive, step: .adventure, ingredients: $0) }

        #expect(clocks.first == TimeOfDay.Moment.dawn.clock)
        #expect(clocks.last == TimeOfDay.Moment.morning.clock)
        // Every ingredient found moves the sun on.
        #expect(zip(clocks, clocks.dropFirst()).allSatisfy { $0 < $1 })
        // Angering the dragon does not change the hour.
        #expect(TimeOfDay.target(phase: .alerted, step: .adventure, ingredients: 2)
                == TimeOfDay.target(phase: .captive, step: .adventure, ingredients: 2))
    }

    @Test func untanglingIsNoonAndTheFarewellIsSunset() {
        for phase in [DragonPhase.approaching, .landing, .untangling] {
            #expect(TimeOfDay.target(phase: phase, step: .adventure, ingredients: 3) == TimeOfDay.Moment.noon.clock)
        }
        #expect(TimeOfDay.target(phase: .free, step: .gratitude, ingredients: 3) == TimeOfDay.Moment.goldenHour.clock)
        #expect(TimeOfDay.target(phase: .free, step: .farewell, ingredients: 3) == TimeOfDay.Moment.sunset.clock)
        #expect(TimeOfDay.target(phase: .gone, step: .adventure, ingredients: 3) == TimeOfDay.Moment.sunset.clock)
    }

    @Test func eachMomentHasExactlyItsOwnLight() {
        for moment in TimeOfDay.Moment.allCases {
            #expect(TimeOfDay.daylight(at: moment.clock) == moment.daylight)
        }
    }

    @Test func theSunRisesToNoonThenSetsFromLeftToRight() {
        let samples = (0...50).map { TimeOfDay.daylight(at: Float($0) / 50) }
        let noon = samples.indices.max { samples[$0].sunElevation < samples[$1].sunElevation } ?? 0

        #expect(abs(Float(noon) / 50 - TimeOfDay.Moment.noon.clock) < 0.03)
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0.sunAzimuth <= $1.sunAzimuth })
        // Always above the horizon: the light never comes from below the floor.
        #expect(samples.allSatisfy { $0.sunElevation > 0 && $0.towardsSun.y > 0 })
        #expect(samples.allSatisfy { abs(simd_length($0.towardsSun) - 1) < 1e-4 })
        // Sky: dawn, then noon, then sunset.
        #expect(samples.first?.skyBlend == 0)
        #expect(samples.last?.skyBlend == 2)
    }

    @Test func theClockRunsSmoothlyAndNeverOvershoots() {
        var clock: Float = 0
        var frames = 0
        while clock < TimeOfDay.Moment.noon.clock, frames < 10_000 {
            let next = TimeOfDay.advance(clock, toward: TimeOfDay.Moment.noon.clock, deltaTime: 1 / 90)
            #expect(next - clock <= TimeOfDay.forwardSpeed / 90 + 1e-6)
            clock = next
            frames += 1
        }
        #expect(clock == TimeOfDay.Moment.noon.clock)
        // Dawn to noon takes several seconds: the player sees the day moving on.
        #expect(Float(frames) / 90 > 4)
    }

    @Test func restartingRewindsQuickly() {
        var clock = TimeOfDay.Moment.sunset.clock
        var seconds: Float = 0
        while clock > 0, seconds < 10 {
            clock = TimeOfDay.advance(clock, toward: 0, deltaTime: 0.1)
            seconds += 0.1
        }
        #expect(clock == 0)
        #expect(seconds < 2)
    }

    @Test func theSkyGoesFromTheZenithToTheGround() {
        for gradient in SkyGradient.all {
            #expect(simd_distance(gradient.color(atElevation: .pi / 2), gradient.zenith) < 1e-5)
            #expect(simd_distance(gradient.color(atElevation: 0), gradient.horizon) < 1e-5)
            #expect(simd_distance(gradient.color(atElevation: -.pi / 2), gradient.ground) < 1e-5)
        }
    }

    @MainActor
    @Test func theDebugClockHoldsTheLightAndResetGoesBackToDawn() {
        let sky = SkyViewModel()
        sky.debugClock = TimeOfDay.Moment.sunset.clock
        for _ in 0..<2_000 { sky.advance(toward: 0, deltaTime: 0.02) }

        #expect(sky.clock == TimeOfDay.Moment.sunset.clock)
        #expect(sky.moment == .sunset)
        #expect(sky.roomTint == TimeOfDay.Moment.sunset.daylight.roomTint)

        sky.reset()
        #expect(sky.clock == 0)
        #expect(sky.debugClock == nil)
        #expect(sky.moment == .dawn)
    }
}
