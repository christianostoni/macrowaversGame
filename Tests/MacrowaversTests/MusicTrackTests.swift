import Testing
@testable import Macrowavers

struct MusicTrackTests {
    @Test func silentUntilTheIslandOpens() {
        #expect(MusicTrack.playing(story: .start, dragon: .captive) == nil)
    }

    @Test func introUnderThePagesAndTheFruit() {
        for step in [StoryStep.scroll, .chapter, .adventure] {
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
        #expect(!MusicTrack.farewell.loops)
    }

    @Test func theRideTrackFromTheArrivalToTheMedallion() {
        for step in [StoryStep.ride, .secondChapter, .feast, .finale] {
            #expect(MusicTrack.riding(story: step) == .ride)
        }
        #expect(MusicTrack.ride.loops)
    }

    @Test func silenceAsTheRideEndsThroughTheMedallion() {
        // The last pages are back in the room: the ride's space closes, its music fading out.
        for step in [StoryStep.epilogue, .toBeContinued, .ended] {
            #expect(MusicTrack.riding(story: step) == nil)
        }
        // The ride's space only plays what it loads.
        for step in StoryStep.allCases {
            guard let track = MusicTrack.riding(story: step) else { continue }
            #expect(MusicTrack.ridingTracks.contains(track))
        }
    }
}
