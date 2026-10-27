import Testing
@testable import Macrowavers

/// The story's scroll in the player's hands (`StoryScroll`): pulled open (or tapped), its paper dragged to the
/// painting, then rolled up and gone; skipping works at any time, even without its page.
@MainActor
struct StoryScrollTests {
    private func makeScroll() -> StoryScroll {
        let scroll = StoryScroll()
        scroll.roll = ScrollRoll(width: 0.45, pageLength: 1.45)
        scroll.present()
        return scroll
    }

    private func play(_ scroll: StoryScroll, seconds: Float) {
        for _ in 0..<Int(seconds * 60) { scroll.update(deltaTime: 1.0 / 60) }
    }

    @Test func itFadesInClosed() {
        let scroll = makeScroll()
        #expect(scroll.phase == .closed && scroll.open == 0 && scroll.fade == 0)
        play(scroll, seconds: 1)
        #expect(scroll.fade == 1 && scroll.phase == .closed)
    }

    @Test func pulledPastAThirdItOpensAllTheWay() {
        let scroll = makeScroll()
        scroll.drag(height: 1.2)
        scroll.drag(height: 1.05)
        #expect(scroll.open > StoryScroll.openThreshold && scroll.open < 1)
        scroll.endDrag()
        play(scroll, seconds: 2)
        #expect(scroll.phase == .reading && scroll.open == 1)
    }

    @Test func pulledALittleItClosesAgain() {
        let scroll = makeScroll()
        scroll.drag(height: 1.2)
        scroll.drag(height: 1.17)
        #expect(scroll.open > 0)
        scroll.endDrag()
        play(scroll, seconds: 2)
        #expect(scroll.phase == .closed && scroll.open == 0)
    }

    @Test func tappedItOpens() {
        let scroll = makeScroll()
        scroll.tap()
        play(scroll, seconds: 2)
        #expect(scroll.phase == .reading && scroll.open == 1)
    }

    @Test func thePaperFollowsTheHandToThePainting() throws {
        let scroll = makeScroll()
        let roll = try #require(scroll.roll)
        scroll.tap()
        play(scroll, seconds: 2)
        let travel = roll.travel(window: roll.openWindow)
        scroll.drag(height: 1)
        scroll.drag(height: 1 + travel / 2)
        #expect(abs(scroll.scroll - 0.5) < 1e-3 && !scroll.hasReachedEnd)
        scroll.drag(height: 1 + travel + 0.1)
        #expect(scroll.scroll == 1 && scroll.hasReachedEnd)
        scroll.endDrag()
        // Back up to the top: it stays read.
        scroll.drag(height: 1)
        scroll.drag(height: 1 - travel - 0.1)
        scroll.endDrag()
        #expect(scroll.scroll == 0 && scroll.hasReachedEnd && scroll.open == 1)
    }

    @Test func finishedItRollsUpFadesAndIsDone() {
        let scroll = makeScroll()
        scroll.tap()
        play(scroll, seconds: 2)
        scroll.finish()
        #expect(scroll.phase == .closing)
        play(scroll, seconds: 3)
        #expect(scroll.isDone && scroll.fade == 0 && scroll.open < 0.02)
        // Gone: nothing brings it back but the story.
        scroll.tap()
        scroll.drag(height: 1)
        #expect(scroll.isDone)
    }

    @Test func withoutItsPageItCanStillBeSkipped() {
        let scroll = StoryScroll()
        scroll.present()
        scroll.tap()
        scroll.drag(height: 1)
        #expect(scroll.phase == .closed && scroll.open == 0)
        scroll.finish()
        play(scroll, seconds: 1)
        #expect(scroll.isDone)
    }
}
