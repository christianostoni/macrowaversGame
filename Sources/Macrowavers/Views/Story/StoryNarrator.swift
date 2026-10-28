import Foundation
import RealityKit

/// Plays the story's narration (`StoryNarration`): not spatial, in the player's ears like the music, which steps
/// back under it (`DragonImmersiveView`). Started when the scroll opens, faded out when it rolls up.
@MainActor
final class StoryNarrator {
    /// Added to the immersive scene: the voice plays from it.
    let entity = Entity()

    static let level: Audio.Decibel = 0
    static let fadeOut: TimeInterval = 0.8

    private var resource: AudioFileResource?
    private var controller: AudioPlaybackController?

    init() {
        entity.name = "Narrator"
        entity.components.set(ChannelAudioComponent())
    }

    /// Decoded at once (~1 MB): ready to start the moment the scroll opens, in step with its subtitles.
    func load() async {
        resource = await GameAudio.load(StoryNarration.fileName)
    }

    func play() {
        guard controller == nil, let resource else { return }
        let controller = entity.prepareAudio(resource)
        controller.gain = Self.level
        controller.play()
        self.controller = controller
    }

    func stop() {
        guard let controller else { return }
        self.controller = nil
        controller.fade(to: -80, duration: Self.fadeOut)
        Task {
            try? await Task.sleep(for: .seconds(Self.fadeOut))
            controller.stop()
        }
    }
}
