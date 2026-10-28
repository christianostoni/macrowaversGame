import Testing
@testable import Macrowavers

/// Every sound the game loads by name: the island's, the orchard's, the ride's, the medallion's notes and the music.
private let soundNames: [[String]] = [
    DragonEffects.soundNames,
    OrchardSounds.Sound.allCases.map(\.rawValue),
    DragonRideSystem.Sound.allCases.map(\.rawValue),
    DragonRideSystem.petalNotes,
    MusicTrack.allCases.map(\.rawValue)
]

/// Every sound the game plays is in the app bundle and RealityKit can read it: a missing or misnamed file would
/// only show up as silence on the headset.
@MainActor
struct GameAudioTests {
    @Test(arguments: soundNames.joined())
    func soundLoads(name: String) async {
        #expect(await GameAudio.load(name) != nil)
    }
}
