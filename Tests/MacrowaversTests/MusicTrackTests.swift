import Testing
@testable import Macrowavers

struct MusicTrackTests {
    @Test func silentUntilTheIslandOpens() {
        #expect(MusicTrack.playing(story: .start, dragon: .captive) == nil)
    }

    @Test func introUnderThePagesAndTheFruit() {
        for step in [StoryStep.searching, .chapter, .adventure] {
            #expect(MusicTrack.playing(story: step, dragon: .captive) == .intro)
            #expect(MusicTrack.playing(story: step, dragon: .alerted) == .intro)
        }
    }

    @Test func puzzleFromTheFlightToTheKnot() {
        for phase in [DragonPhase.approaching, .landing, .untangling] {
            #expect(MusicTrack.playing(story: .adventure, dragon: phase) == .puzzle)
        }
    }

    @Test func farewellOnceTheDragonIsFree() {
        #expect(MusicTrack.playing(story: .adventure, dragon: .free) == .farewell)
        for step in [StoryStep.gratitude, .safety, .ride] {
            #expect(MusicTrack.playing(story: step, dragon: .free) == .farewell)
        }
        #expect(MusicTrack.playing(story: .ride, dragon: .gone) == .farewell)
        #expect(!MusicTrack.farewell.loops)
    }
}
