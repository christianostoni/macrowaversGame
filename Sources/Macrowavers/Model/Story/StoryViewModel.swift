import Foundation
import Observation

/// View model of the storytelling around the game: which screen is shown (`StoryStep`) and how the player
/// moves through them. It knows nothing about the dragon: the immersive view tells it when the dragon is
/// freed (or captive again) and starts the ride when the story reaches it.
@MainActor
@Observable
final class StoryViewModel {
    private(set) var step = StoryStep.start
    /// Chapter II's tally: the wave, the fruit eaten in it, the dragon's hearts, the fire (`DragonFeast`).
    private(set) var feast = FeastProgress()
    /// The tally's fire button was pressed (the snap's alternative without hand tracking): the ride breathes fire
    /// on its next frame and clears it.
    private(set) var isFireRequested = false

    /// Screen 1: the player presses Start (the immersive space is opening).
    func begin() {
        guard step == .start else { return }
        step = .searching
    }

    /// The player taps the page or answers its question.
    func advance() {
        let next: StoryStep? = switch step {
        case .searching: .chapter
        case .chapter: .adventure
        case .gratitude: .safety
        case .safety: .ride
        case .secondChapter: .feast
        case .finale: .ended
        case .start, .adventure, .ride, .feast, .ended: nil
        }
        if let next { step = next }
    }

    /// The dragon has been untangled: it speaks to the player.
    func dragonFreed() {
        guard step == .adventure else { return }
        step = .gratitude
    }

    /// The dragon is back around the tree (the scene was restarted): back to the game, its words to come.
    func dragonRecaptured() {
        guard step == .gratitude || step == .safety || step.isFullyImmersed else { return }
        step = .adventure
    }

    /// The dragon has come out of the dark with the player on its back: chapter II begins.
    func rideArrived() {
        guard step == .ride else { return }
        feast = FeastProgress()
        step = .secondChapter
        #if DEBUG
        if Self.skipsChapterTitle { step = .feast }
        #endif
    }

    /// The feast moved on (set every frame by the ride: assigned only when it changes, only while feeding).
    func showFeast(_ progress: FeastProgress) {
        guard step == .feast, progress != feast else { return }
        feast = progress
    }

    /// The fire button: like a snap of the fingers (only while feeding).
    func requestFire() {
        guard step == .feast else { return }
        isFireRequested = true
    }

    /// The ride took the fire request. Returns whether there was one.
    func takeFireRequest() -> Bool {
        guard isFireRequested else { return false }
        isFireRequested = false
        return true
    }

    /// The last wave is eaten: the dragon is full, the story's last page.
    func feastFinished() {
        guard step == .feast else { return }
        step = .finale
    }

    #if DEBUG
    /// Debug builds launched with `-StoryStartsAtRide` (Xcode: scheme > Run > Arguments) open straight on the ride,
    /// to try it without playing the whole story.
    static var startsAtRide: Bool { ProcessInfo.processInfo.arguments.contains("-StoryStartsAtRide") }
    /// With `-StorySkipsChapterTitle` too, the fruit appear without waiting for a tap on chapter II's title.
    static var skipsChapterTitle: Bool { ProcessInfo.processInfo.arguments.contains("-StorySkipsChapterTitle") }

    func skipToRide() {
        step = .ride
    }
    #endif

    /// The immersive space closed: back to the Start button.
    func reset() {
        if step != .start { step = .start }
        if feast != FeastProgress() { feast = FeastProgress() }
    }
}
