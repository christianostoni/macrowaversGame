import Foundation

/// Focus mode: what holds the player's attention. Everything else in the scene fades back, so the eyes stay on
/// what they are doing, and comes back when they return to exploring.
/// Pure state: the RealityKit layer reads it (`FocusDimmingSystem`) and fades the entities.
enum SceneFocus: Equatable {
    /// Exploring: everything fully visible.
    case none
    /// A fruit is close to the player: the island, the tree, the other fruit and the dragon fade back.
    case fruit
    /// The dragon settles into the knot and is untangled, or speaks to the player once free: the island, the
    /// tree and the fruit fade back.
    case dragon
    /// The player rides the dragon in the dark sky: the island and the dragon in the room are gone.
    case ride

    /// Parts of the scene that can fade. The focused fruit is never one of them: it sits in front of the player.
    enum Part: Equatable {
        /// The floating island: rock, tree, floating rocks and the fruit hanging on the tree.
        case island
        /// The dragon (body, head, wings, effects).
        case dragon
    }

    /// Opacity of the parts that fade back.
    static let dimmedOpacity: Float = 0.25

    /// - Parameters:
    ///   - isFruitFocused: a fruit has been brought close to the player.
    ///   - isElixirFlying: the elixir is on its way to the dragon: the scene comes back so the player
    ///     can follow it, even though the fruit is still close.
    ///   - phase: the dragon's chapter.
    ///   - isDragonSpeaking: the story shows the dragon's words (`StoryStep.focusesOnDragon`).
    ///   - isRiding: the story's ride has begun (`StoryStep.isFullyImmersed`).
    init(isFruitFocused: Bool, isElixirFlying: Bool, phase: DragonPhase, isDragonSpeaking: Bool = false,
         isRiding: Bool = false) {
        if isRiding {
            self = .ride
        } else if isFruitFocused && !isElixirFlying {
            self = .fruit
        } else if phase.focusesOnDragon || isDragonSpeaking {
            self = .dragon
        } else {
            self = .none
        }
    }

    /// Opacity the part should fade to.
    func opacity(of part: Part) -> Float {
        switch (self, part) {
        case (.none, _), (.dragon, .dragon): 1
        case (.fruit, _), (.dragon, .island): Self.dimmedOpacity
        case (.ride, _): 0
        }
    }
}
