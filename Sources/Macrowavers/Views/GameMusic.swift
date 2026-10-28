import Foundation
import RealityKit

/// Plays the story's music (`MusicTrack`): not spatial, it stays in the player's ears wherever they look. A new
/// track fades in over the old one; the music steps back while the dragon roars.
@MainActor
final class GameMusic {
    /// Added to the immersive scene: the music plays from it.
    let entity = Entity()

    static let level: Audio.Decibel = -14
    static let duckedLevel: Audio.Decibel = -26
    static let crossfade: TimeInterval = 2

    private var resources: [MusicTrack: AudioFileResource] = [:]
    /// The track the story asks for: it starts as soon as it is loaded.
    private var wanted: MusicTrack?
    private var playing: (track: MusicTrack, controller: AudioPlaybackController)?
    private var isDucked = false

    init() {
        entity.name = "Music"
        entity.components.set(ChannelAudioComponent())
    }

    /// `tracks`: the ones this space plays.
    func load(_ tracks: [MusicTrack] = MusicTrack.allCases) async {
        for track in tracks {
            resources[track] = await GameAudio.load(track.rawValue, loops: track.loops, streams: true)
        }
        play(wanted)
    }

    func play(_ track: MusicTrack?) {
        wanted = track
        guard track != playing?.track else { return }
        if let old = playing?.controller { Self.fadeOut(old) }
        playing = nil
        guard let track, let resource = resources[track] else { return }
        // Prepared silent, then faded in: started at full level it would cut in over the old track.
        let controller = entity.prepareAudio(resource)
        controller.gain = -80
        controller.play()
        controller.fade(to: isDucked ? Self.duckedLevel : Self.level, duration: Self.crossfade)
        playing = (track, controller)
    }

    /// Softer while the dragon roars, so the roar is heard.
    func duck(_ ducked: Bool) {
        guard ducked != isDucked else { return }
        isDucked = ducked
        playing?.controller.fade(to: ducked ? Self.duckedLevel : Self.level, duration: ducked ? 0.3 : 1.5)
    }

    private static func fadeOut(_ controller: AudioPlaybackController) {
        controller.fade(to: -80, duration: crossfade)
        Task {
            try? await Task.sleep(for: .seconds(crossfade))
            controller.stop()
        }
    }
}
