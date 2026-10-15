import Foundation

/// Focus mode: what holds the player's attention. Everything else in the scene fades back, so the eyes stay on
/// what they are doing, and comes back when they return to exploring.
/// Pure state: the RealityKit layer reads it (`FocusDimmingSystem`) and fades the entities.
enum SceneFocus: Equatable {
    /// Exploring: everything fully visible.
    case none
    /// A fruit is close to the player: the island, the tree, the other fruit and the dragon fade back.
    case fruit
    /// The dragon settles into the knot and is untangled: the island, the tree and the fruit fade back.
    case dragon

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
    ///   - isArtifactFlying: the artifact is on its way to the dragon: the scene comes back so the player
    ///     can follow it, even though the fruit is still close.
    ///   - phase: the dragon's chapter.
    init(isFruitFocused: Bool, isArtifactFlying: Bool, phase: DragonPhase) {
        if isFruitFocused && !isArtifactFlying {
            self = .fruit
        } else if phase.focusesOnDragon {
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
        }
    }
}
