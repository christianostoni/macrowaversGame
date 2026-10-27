import Foundation
import Observation

/// View model of the storytelling around the game: which screen is shown (`StoryStep`) and how the player
/// moves through them. It knows nothing about the dragon: the immersive view tells it when the dragon is
/// freed (or captive again) and starts the ride when the story reaches it.
@MainActor
@Observable
final class StoryViewModel {
    private(set) var step = StoryStep.start
    /// Chapter II: the fruit the dragon has eaten (bananas don't count: it spits them out).
    private(set) var plantsEaten = 0
    /// Bananas the player fed it anyway.
    private(set) var bananasRefused = 0
    /// The dragon has flown into the shamseh: the ride is over (the immersive space closes).
    private(set) var isRideOver = false

    /// Fruit to feed the dragon in chapter II.
    static let plantsGoal = 8

    var isFeastComplete: Bool { plantsEaten >= Self.plantsGoal }

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
        case .start, .adventure, .ride, .feast, .finale: nil
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
        plantsEaten = 0
        bananasRefused = 0
        step = .secondChapter
        #if DEBUG
        if Self.skipsChapterTitle { step = .feast }
        #endif
    }

    /// The dragon bit into a fruit in the sky (only while the player feeds it).
    func dragonAte(_ fruit: FruitKind) {
        guard step == .feast else { return }
        if fruit.isLikedByDragon {
            plantsEaten += 1
        } else {
            bananasRefused += 1
        }
    }

    /// The dragon is full and its medallion complete: it flies off into it.
    func feastCelebrated() {
        guard step == .feast, isFeastComplete else { return }
        step = .finale
    }

    /// The dragon has flown into the heart of the medallion: the end, for now.
    func rideEnded() {
        guard step == .finale else { return }
        isRideOver = true
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
        plantsEaten = 0
        bananasRefused = 0
        isRideOver = false
    }
}
