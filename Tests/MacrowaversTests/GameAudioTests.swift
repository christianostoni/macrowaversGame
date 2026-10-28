import Testing
@testable import Macrowavers

/// Every sound the game plays is in the app bundle and RealityKit can read it: a missing or misnamed file would
/// only show up as silence on the headset.
@MainActor
struct GameAudioTests {
    @Test(arguments: DragonEffects.soundNames + OrchardSounds.Sound.allCases.map(\.rawValue)
        + DragonRideSystem.Sound.allCases.map(\.rawValue) + MusicTrack.allCases.map(\.rawValue))
    func soundLoads(name: String) async {
        #expect(await GameAudio.load(name) != nil)
    }
}
