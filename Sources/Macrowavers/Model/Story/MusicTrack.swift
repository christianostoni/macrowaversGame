import Foundation

/// The music under each part of the story: the file in the bundle (`rawValue`) and when it plays.
enum MusicTrack: String, CaseIterable {
    /// The narrator's pages and the gathering of the fruit, while the dragon is still on the island: a calm setar.
    case intro = "MusicIntro"
    /// From the moment the soothed dragon flies to the player until it is untangled.
    case puzzle = "MusicPuzzle"
    /// The freed dragon thanks the player and takes them on its back. Long enough to play once.
    case farewell = "MusicFarewell"

    var loops: Bool { self != .farewell }

    /// What plays at this point of the story (nil: silence, the immersive space is not open yet).
    static func playing(story: StoryStep, dragon: DragonPhase) -> MusicTrack? {
        switch (story, dragon) {
        case (.start, _): nil
        case (.gratitude, _), (.safety, _), (.ride, _), (.secondChapter, _), (.feast, _), (.finale, _),
             (_, .free), (_, .gone):
            .farewell
        case (_, .approaching), (_, .landing), (_, .untangling): .puzzle
        default: .intro
        }
    }
}
