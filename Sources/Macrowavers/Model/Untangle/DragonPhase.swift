import Foundation

/// Chapters of the dragon's story: from the floating island, to the tangle, to freedom.
enum DragonPhase: Equatable {
    /// Captive on the island: circles the tree and waits for the player to tap it.
    case captive
    /// Tapped while on the island: it gets angry (glares, growls, smoke) and circles faster for a while.
    /// The dragon panel shows its state; the artifact from the tree's fruit is what calms it.
    case alerted
    /// Soothed: flies to the player and stops in front of them.
    case approaching
    /// Settles in front of the player, tracing the knot with its own body.
    case landing
    /// The mini-game: the player untangles it.
    case untangling
    /// Untangled: celebrates, thanks the player and flies away into the sky.
    case free
    /// Flown away: the story is over.
    case gone

    enum Interaction {
        /// The body does not respond (the dragon is flying).
        case none
        /// Tapping the dragon makes it angry.
        case tap
        /// Every part of the body can be grabbed and dragged (one per hand).
        case grab
    }

    /// Still on the island (circling the tree, calm or angry): the fruit can be picked and the artifact used.
    var isOnIsland: Bool { self == .captive || self == .alerted }

    /// The dragon is the centre of attention (settling into the knot, being untangled): the island and the
    /// fruit around it fade back so the player's eyes stay on the knot.
    var focusesOnDragon: Bool { self == .landing || self == .untangling }

    var interaction: Interaction {
        switch self {
        case .captive, .alerted: .tap
        case .untangling: .grab
        case .approaching, .landing, .free, .gone: .none
        }
    }
}
