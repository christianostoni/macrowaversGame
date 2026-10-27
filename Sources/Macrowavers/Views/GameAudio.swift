import Foundation
import RealityKit

/// The game's sound files: in the app bundle by name (`Resources/`, m4a, wav, mp3 or caf), mono for spatial audio.
enum GameAudio {
    /// nil when the file is missing (the sound stays silent) or cannot be read. `streams`: read from the file while
    /// it plays (the music: preloaded, its minutes of decoded audio took ~150 MB) instead of decoded at once (the
    /// short sounds, ready to start without delay).
    @MainActor
    static func load(_ name: String, loops: Bool = false, streams: Bool = false) async -> AudioFileResource? {
        let file = ["m4a", "wav", "mp3", "caf"].map { name + "." + $0 }
            .first { Bundle.main.url(forResource: $0, withExtension: nil) != nil }
        guard let file else { return nil }
        var configuration = AudioFileResource.Configuration(shouldLoop: loops)
        configuration.loadingStrategy = streams ? .stream : .preload
        return try? await AudioFileResource(named: file, configuration: configuration)
    }
}
