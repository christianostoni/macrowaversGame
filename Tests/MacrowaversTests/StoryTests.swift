import Testing
import simd
@testable import Macrowavers

@MainActor
struct StoryTests {
    @Test func theStoryWalksThroughTheFiveScreens() {
        let story = StoryViewModel()
        #expect(story.step == .start)
        // Before Start nothing moves the story on.
        story.advance()
        story.dragonFreed()
        #expect(story.step == .start)

        story.begin()
        #expect(story.step == .searching)
        story.advance()
        #expect(story.step == .chapter)
        story.advance()
        #expect(story.step == .adventure)

        // Tapping does nothing during the game: only freeing the dragon brings its words.
        story.advance()
        #expect(story.step == .adventure)
        story.dragonFreed()
        #expect(story.step == .gratitude)
        story.advance()
        #expect(story.step == .safety)
        story.advance()
        #expect(story.step == .farewell)
        story.advance()
        #expect(story.step == .farewell)
    }

    @Test func restartingTheDragonOrTheSpaceGoesBack() {
        let story = StoryViewModel()
        story.begin()
        story.advance()
        story.advance()
        story.dragonFreed()
        story.advance()
        story.dragonRecaptured()
        #expect(story.step == .adventure)
        // A recapture during the intro does not skip anything.
        let intro = StoryViewModel()
        intro.begin()
        intro.dragonRecaptured()
        #expect(intro.step == .searching)

        story.reset()
        #expect(story.step == .start)
    }

    @Test func pagesDimTheRoomAndSitWhereTheWireframesPutThem() {
        for step in StoryStep.allCases {
            #expect(step.dimsSurroundings == (step.page != nil))
        }
        #expect(StoryStep.start.page == nil)
        #expect(StoryStep.searching.page?.anchor == .viewer)
        #expect(StoryStep.chapter.page?.anchor == .viewer)
        #expect(StoryStep.gratitude.page?.anchor == .dragon)
        #expect(StoryStep.safety.page?.anchor == .dragon)
        // The last question needs an explicit answer.
        #expect(StoryStep.safety.page?.advance == .answer("I'm Ready"))
        #expect(StoryStep.gratitude.focusesOnDragon && !StoryStep.chapter.focusesOnDragon)
        // The island appears only after the chapter's title.
        #expect(StoryStep.allCases.filter { !$0.revealsWorld } == [.start, .searching, .chapter])
        // No placeholder text left from the wireframes.
        let text = StoryStep.allCases.compactMap(\.page).flatMap { [$0.title] + $0.lines }
        #expect(!text.contains { $0.contains("XXX") })
    }
}

@MainActor
struct FarewellCueTests {
    private func play(_ viewModel: UntangleViewModel, seconds: Float) {
        let orbit = AnchoredOrbit(path: .aroundTree, worldFromAnchor: IslandPlacement.standard.transform)
        for _ in 0..<Int(seconds * 60) {
            viewModel.update(deltaTime: 1.0 / 60.0, viewer: SIMD3(0, 1.15, 0), worldFromLocal: matrix_identity_float4x4,
                             orbit: orbit)
        }
    }

    /// Calls the dragon into a knot with no crossings: it is free as soon as it settles.
    private func freeDragon(waitsForPlayer: Bool) -> UntangleViewModel {
        let viewModel = UntangleViewModel(shape: .loop, farewellWaitsForPlayer: waitsForPlayer)
        play(viewModel, seconds: 1.0 / 60.0)
        viewModel.callDragon()
        var elapsed: Float = 0
        while viewModel.phase != .free && elapsed < 30 {
            play(viewModel, seconds: 0.5)
            elapsed += 0.5
        }
        return viewModel
    }

    @Test func theFreeDragonWaitsUntilThePlayerIsReady() {
        let viewModel = freeDragon(waitsForPlayer: true)
        #expect(viewModel.phase == .free)
        // It speaks to the player for as long as they need.
        play(viewModel, seconds: 10)
        #expect(viewModel.phase == .free && !viewModel.isFlying)

        viewModel.beginFarewell()
        play(viewModel, seconds: 0.1)
        #expect(viewModel.isFlying)

        // Restarting the scene forgets the answer: next time it waits again.
        viewModel.restartScene()
        #expect(!viewModel.isFlying)
    }

    @Test func withoutTheStoryItTakesOffOnItsOwn() {
        let viewModel = freeDragon(waitsForPlayer: false)
        #expect(viewModel.phase == .free)
        play(viewModel, seconds: 2)
        #expect(viewModel.isFlying)
    }
}
