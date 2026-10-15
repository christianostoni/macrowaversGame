import Foundation
import Observation

/// View model of the storytelling around the game: which screen is shown (`StoryStep`) and how the player
/// moves through them. It knows nothing about the dragon: the immersive view tells it when the dragon is
/// freed (or captive again) and starts the dragon's farewell when the story reaches it.
@MainActor
@Observable
final class StoryViewModel {
    private(set) var step = StoryStep.start

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
        case .safety: .farewell
        case .start, .adventure, .farewell: nil
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
        guard step == .gratitude || step == .safety || step == .farewell else { return }
        step = .adventure
    }

    /// The immersive space closed: back to the Start button.
    func reset() {
        if step != .start { step = .start }
    }
}
