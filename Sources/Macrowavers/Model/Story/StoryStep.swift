import Foundation

/// The storytelling screens around the game, in order: the start, the story's scroll and the chapter's title
/// before the island appears, the game itself, the dragon's words once it is free, then the ride on its back: chapter
/// II, where the player feeds the dragon in the sky, the sky harder as they do well, until it is full and flies into the star
/// medallion its fruit lit up, and the story pauses: the next chapter is still being written.
enum StoryStep: Equatable, CaseIterable {
    /// Screen 1: a lone "Start" button in the room (the launch window).
    case start
    /// Screen 2: the story's scroll (`StoryScroll`): the player opens it and reads the chapter's story in Persian,
    /// down to its painting of the tree and the dragon.
    case scroll
    /// Screen 3: the chapter's title and its proverb.
    case chapter
    /// No story text: the island, its fruit and the dragon's puzzle.
    case adventure
    /// Screen 4: the freed dragon thanks the player.
    case gratitude
    /// Screen 5: the dragon offers to take the player to safety.
    case safety
    /// The player is ready: the room goes dark (full immersion) and they fly on the dragon's back, steering it
    /// with both hands, out of the dark into the sky.
    case ride
    /// Over the clouds: chapter II's goal (its name was shown while the ride loaded).
    case secondChapter
    /// Fruit float in the sky, harder as the player does well: they steer the dragon into the ones it likes (not the
    /// bananas, not the poisoned ones: fire burns those away) (`DragonFeast`).
    case feast
    /// The dragon is full: it flies on its own into the heart of the shamseh, in a rush of light, and through it.
    case finale
    /// Through the medallion the ride's space closes: back in the room, in the launch window, chapter II's last
    /// page, and a hint of what comes next.
    case epilogue
    /// Still in the room: the story will go on, in chapters still being written.
    case toBeContinued
    /// The player closed the story: the system asks them to rate the game, over the Start button.
    case ended

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

    /// A page of text: a short title (none when empty) and its lines.
    struct Page: Equatable {
        let title: String
        let lines: [String]
        let anchor: Anchor
        let advance: Advance
    }

    /// The text of the screens shown inside the immersive space (`start` is the launch window's button).
    var page: Page? {
        switch self {
        case .start, .scroll, .adventure, .ride, .feast, .finale, .ended:
            nil
        case .chapter:
            Page(title: "Chapter I", lines: ["Patience is bitter, but its fruit is sweet."],
                 anchor: .viewer, advance: .tap)
        case .gratitude:
            Page(title: "Thank you", lines: ["You freed me from the curse of the Black Div.", "You don't need to be afraid."],
                 anchor: .dragon, advance: .tap)
        case .safety:
            Page(title: "Thank you", lines: ["Child of the Shah, I will take you to safety.", "Are you ready?"],
                 anchor: .dragon, advance: .answer("I'm Ready"))
        case .secondChapter:
            // Named while the ride loaded (`rideTitle`): only its goal, without a title.
            Page(title: "", lines: ["Feed the dragon the right plants."], anchor: .viewer, advance: .tap)
        case .epilogue:
            Page(title: "Home at last", lines: ["The curse is gone, and the dragon is full.",
                                                "But far beyond the clouds, the Black Div stirs…"],
                 anchor: .viewer, advance: .tap)
        case .toBeContinued:
            Page(title: "To be continued", lines: ["The next chapter is still being written."],
                 anchor: .viewer, advance: .answer("Until next time"))
        }
    }

    /// Chapter II's last pages, back in the room (the launch window): its ending, then the promise of more.
    var isLastPages: Bool { self == .epilogue || self == .toBeContinued }

    /// Chapter II's name, over the ride's loading animation while its sky is built (`DragonRideView`): the wait in the
    /// dark opens the chapter as chapter I's title does. No step of its own: it goes once the sky is built and read.
    static let rideTitle = Page(title: "Chapter II", lines: ["Havā-tō dāram: I have your back"],
                                anchor: .viewer, advance: .tap)

    /// The room is darkened so the eyes stay on the words, the scroll's included (and on the dragon, when it speaks).
    var dimsSurroundings: Bool { page != nil || self == .scroll }

    /// The island, its fruit and the dragon are in the room (they appear after the chapter's title).
    var revealsWorld: Bool {
        switch self {
        case .start, .scroll, .chapter: false
        case .adventure, .gratitude, .safety, .ride, .secondChapter, .feast, .finale, .epilogue, .toBeContinued,
             .ended: true
        }
    }

    /// The dragon is talking to the player: the island fades back behind it.
    var focusesOnDragon: Bool { page?.anchor == .dragon }

    /// The room is gone: the player is in the sky (full immersion), on the dragon's back.
    var isFullyImmersed: Bool {
        switch self {
        case .ride, .secondChapter, .feast, .finale: true
        case .start, .scroll, .chapter, .adventure, .gratitude, .safety, .epilogue, .toBeContinued, .ended: false
        }
    }
}
