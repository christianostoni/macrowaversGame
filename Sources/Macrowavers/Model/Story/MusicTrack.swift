import Foundation

/// The music under each part of the story: the file in the bundle (`rawValue`) and when it plays.
enum MusicTrack: String, CaseIterable {
    /// The narrator's pages and the gathering of the fruit, while the dragon is still on the island: a calm setar.
    case intro = "MusicIntro"
    /// From the moment the soothed dragon flies to the player until it is untangled.
    case puzzle = "MusicPuzzle"
    /// The freed dragon thanks the player and takes them on its back. Long enough to play once.
    case farewell = "MusicFarewell"
    /// On the dragon's back, from the dark arrival through chapter II to the medallion's heart.
    case ride = "MusicRide"

    var loops: Bool { self != .farewell }

    /// What plays on the island (`DragonImmersiveView`) at this point of the story (nil: silence, the immersive
    /// space is not open yet). The ride's steps keep the farewell: the island's space closes as the ride begins.
    static func playing(story: StoryStep, dragon: DragonPhase) -> MusicTrack? {
        switch (story, dragon) {
        case (.start, _): nil
        case (.gratitude, _), (.safety, _), (.ride, _), (.secondChapter, _), (.feast, _), (.finale, _),
             (.epilogue, _), (.toBeContinued, _), (.ended, _), (_, .free):
            .farewell
        case (_, .approaching), (_, .landing), (_, .untangling): .puzzle
        default: .intro
        }
    }

    /// What plays in the ride's own space (`DragonRideView`): the ride's track from the dark arrival to the
    /// medallion's heart; silence as the space closes (the last pages are back in the room).
    static func riding(story: StoryStep) -> MusicTrack? {
        switch story {
        case .ride, .secondChapter, .feast, .finale: .ride
        default: nil
        }
    }

    /// The tracks the ride's space plays.
    static let ridingTracks: [MusicTrack] = [.ride]
}
