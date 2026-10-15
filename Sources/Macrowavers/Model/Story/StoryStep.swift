import Foundation

/// The storytelling screens around the game, in order: the start, the narrator's words before the island
/// appears, the game itself, then the dragon's words once it is free.
enum StoryStep: Equatable, CaseIterable {
    /// Screen 1: a lone "Start" button in the room (the launch window).
    case start
    /// Screen 2: the narrator asks the player what they are looking for.
    case searching
    /// Screen 3: the chapter's title and its proverb.
    case chapter
    /// No story text: the island, its fruit and the dragon's puzzle.
    case adventure
    /// Screen 4: the freed dragon thanks the player.
    case gratitude
    /// Screen 5: the dragon offers to take the player to safety.
    case safety
    /// The player is ready: the dragon flies away. The story is over.
    case farewell

    /// Where a page is shown.
    enum Anchor: Equatable {
        /// In front of the player's eyes.
        case viewer
        /// Above the dragon: it is the dragon speaking.
        case dragon
    }

    /// How the player moves on from a page.
    enum Advance: Equatable {
        /// Tapping the text goes to the next page.
        case tap
        /// An explicit answer to the page's question (its button label).
        case answer(String)
    }

    /// A page of text: a short title and its lines.
    struct Page: Equatable {
        let title: String
        let lines: [String]
        let anchor: Anchor
        let advance: Advance
    }

    /// The text of the screens shown inside the immersive space (`start` is the launch window's button).
    var page: Page? {
        switch self {
        case .start, .adventure, .farewell:
            nil
        case .searching:
            Page(title: "What are you searching for?", lines: ["I can see you are eager to find…"],
                 anchor: .viewer, advance: .tap)
        case .chapter:
            Page(title: "Chapter I", lines: ["Patience is bitter, but its fruit is sweet."],
                 anchor: .viewer, advance: .tap)
        case .gratitude:
            Page(title: "Thank you", lines: ["You freed me from the curse.", "You don't need to be afraid."],
                 anchor: .dragon, advance: .tap)
        case .safety:
            Page(title: "Thank you", lines: ["I will take you to safety. Are you ready?"],
                 anchor: .dragon, advance: .answer("I'm Ready"))
        }
    }

    /// The room is darkened so the eyes stay on the words (and on the dragon, when it speaks).
    var dimsSurroundings: Bool { page != nil }

    /// The island, its fruit and the dragon are in the room (they appear after the chapter's title).
    var revealsWorld: Bool {
        switch self {
        case .start, .searching, .chapter: false
        case .adventure, .gratitude, .safety, .farewell: true
        }
    }

    /// The dragon is talking to the player: the island fades back behind it.
    var focusesOnDragon: Bool { page?.anchor == .dragon }
}
