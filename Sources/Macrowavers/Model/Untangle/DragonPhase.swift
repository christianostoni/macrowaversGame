import Foundation

/// Chapters of the dragon's story: from the floating island, to the tangle, to freedom.
enum DragonPhase: Equatable {
    /// Captive on the island: circles the tree and waits for the player to tap it.
    case captive
    /// Tapped while on the island: it gets angry (glares, growls, smoke) and circles faster for a while.
    /// The elixir brewed from the tree's fruit is what calms it.
    case alerted
    /// The elixir is on its way: it slows down to a stop on its path around the tree and lifts its head, and the
    /// flask pours the elixir over it. Still on the island; called once the elixir is poured.
    case receivingElixir
    /// Soothed: flies to the player and stops in front of them.
    case approaching
    /// Settles in front of the player, tracing the knot with its own body.
    case landing
    /// The mini-game: the player untangles it.
    case untangling
    /// Untangled: celebrates in the play area and thanks the player; when they are ready the ride takes over
    /// (`DragonRideView`).
    case free

    enum Interaction {
        /// The body does not respond (the dragon is flying).
        case none
        /// Tapping the dragon makes it angry.
        case tap
        /// Every part of the body can be grabbed and dragged (one per hand).
        case grab
    }

    /// Still on the island (circling the tree, calm or angry, or stopped for the elixir): the fruit can be picked
    /// and the elixir used; the dragon flies in the island's space.
    var isOnIsland: Bool { self == .captive || self == .alerted || self == .receivingElixir }

    /// The dragon is the centre of attention (settling into the knot, being untangled): the island and the
    /// fruit around it fade back so the player's eyes stay on the knot.
    var focusesOnDragon: Bool { self == .landing || self == .untangling }

    var interaction: Interaction {
        switch self {
        case .captive, .alerted: .tap
        case .untangling: .grab
        case .receivingElixir, .approaching, .landing, .free: .none
        }
    }
}
