import Foundation
import RealityKit

/// Plays the story's music (`MusicTrack`): not spatial, it stays in the player's ears wherever they look. A new
/// track comes in over the old one, which keeps playing under it for a while (no gap between the two); the music steps
/// back while the dragon roars.
@MainActor
final class GameMusic {
    /// Added to the immersive scene: the music plays from it.
    let entity = Entity()

    static let level: Audio.Decibel = -14
    static let duckedLevel: Audio.Decibel = -26
    /// A new track rises from this gain to `level` in `fadeIn`. Not from silence: faded in from −80 dB while the old
    /// track faded out to −80 dB over the same 2 s, both were inaudible for over a second (fades run in decibels), and
    /// with the farewell's own quiet first second the music seemed to stop and start over when the dragon was freed.
    static let fadeInFloor: Audio.Decibel = -24
    static let fadeIn: TimeInterval = 1.5
    /// The old track fades out under the new one, down to `silence` in `fadeOut`, then stops.
    static let silence: Audio.Decibel = -60
    static let fadeOut: TimeInterval = 6

    private var resources: [MusicTrack: AudioFileResource] = [:]
    /// Controllers prepared ahead, never played: a track starts without opening its stream in the frame that asks for
    /// it (the frame the dragon is freed is busy enough).
    private var ready: [MusicTrack: AudioPlaybackController] = [:]
    /// Tracks playing: the current one and the ones still fading out under it.
    private var voices: [MusicTrack: AudioPlaybackController] = [:]
    /// Bumped on every fade, so a fade-out's delayed stop only stops a track nobody has asked for again since.
    private var fades: [MusicTrack: Int] = [:]
    /// The track the story asks for: it starts as soon as it is loaded.
    private var wanted: MusicTrack?
    private var playing: MusicTrack?
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
        // Once in the scene (the RealityView adds the entity first); otherwise each track is prepared when it starts.
        if entity.scene != nil {
            for track in tracks { prepare(track) }
        }
        play(wanted)
    }

    func play(_ track: MusicTrack?) {
        wanted = track
        guard track != playing else { return }
        if let old = playing { fadeOut(old) }
        playing = nil
        guard let track else { return }
        let target = isDucked ? Self.duckedLevel : Self.level
        fades[track, default: 0] += 1
        if let voice = voices[track], voice.isPlaying {
            // Asked for again while it fades out: it comes back from where it is, it does not start over.
            voice.fade(to: target, duration: Self.fadeIn)
        } else {
            guard let controller = ready.removeValue(forKey: track)
                    ?? resources[track].map({ entity.prepareAudio($0) }) else { return }
            controller.gain = Self.fadeInFloor
            controller.play()
            controller.fade(to: target, duration: Self.fadeIn)
            voices[track] = controller
        }
        playing = track
    }

    /// Softer while the dragon roars, so the roar is heard.
    func duck(_ ducked: Bool) {
        guard ducked != isDucked else { return }
        isDucked = ducked
        guard let playing else { return }
        voices[playing]?.fade(to: ducked ? Self.duckedLevel : Self.level, duration: ducked ? 0.3 : 1.5)
    }

    private func prepare(_ track: MusicTrack) {
        guard ready[track] == nil, let resource = resources[track] else { return }
        ready[track] = entity.prepareAudio(resource)
    }

    private func fadeOut(_ track: MusicTrack) {
        guard let voice = voices[track] else { return }
        voice.fade(to: Self.silence, duration: Self.fadeOut)
        let fade = fades[track, default: 0] + 1
        fades[track] = fade
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.fadeOut))
            guard let self, self.fades[track] == fade else { return }
            voice.stop()
            self.voices[track] = nil
            // Not prepared again here: opening a stream on the main actor 6 s after the dragon is called landed right
            // as it started to coil into the knot, and stuttered. A track asked for again is prepared then.
        }
    }
}
