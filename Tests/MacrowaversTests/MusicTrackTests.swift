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

    @Test func theMusicChangesOnceAtTheKnotAndOnceWhenTheDragonIsFree() {
        // From the poured elixir to the ride, in the order the island's space sees it: the frame the dragon is freed,
        // before the story makes it speak, included. Settling into the knot changes nothing; nothing starts over.
        let journey: [(story: StoryStep, dragon: DragonPhase)] = [
            (.adventure, .receivingElixir), (.adventure, .approaching), (.adventure, .landing),
            (.adventure, .untangling), (.adventure, .free), (.gratitude, .free), (.safety, .free), (.ride, .free),
        ]
        let tracks = journey.map { MusicTrack.playing(story: $0.story, dragon: $0.dragon) }
        let changes = zip(tracks, tracks.dropFirst()).filter { $0 != $1 }.map(\.1)

        #expect(tracks.first == .intro)
        #expect(changes == [.puzzle, .farewell])
    }

    @Test func theRideTrackFromTheArrivalToTheMedallion() {
        for step in [StoryStep.ride, .secondChapter, .feast, .feastFailed, .finale] {
            #expect(MusicTrack.riding(story: step) == .ride)
        }
        #expect(MusicTrack.ride.loops)
    }

    @Test func theFarewellUnderTheLastPageThenSilence() {
        #expect(MusicTrack.riding(story: .epilogue) == .farewell)
        #expect(MusicTrack.riding(story: .ended) == nil)
        // The ride's space only plays what it loads.
        for step in StoryStep.allCases {
            guard let track = MusicTrack.riding(story: step) else { continue }
            #expect(MusicTrack.ridingTracks.contains(track))
        }
    }
}
