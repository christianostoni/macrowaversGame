import Foundation
import RealityKit

/// The game's sound files: in the app bundle by name (`Resources/`, m4a, wav, mp3 or caf), mono for spatial audio.
enum GameAudio {
    /// nil when the file is missing (the sound stays silent) or cannot be read.
    @MainActor
    static func load(_ name: String, loops: Bool = false) async -> AudioFileResource? {
        let file = ["m4a", "wav", "mp3", "caf"].map { name + "." + $0 }
            .first { Bundle.main.url(forResource: $0, withExtension: nil) != nil }
        guard let file else { return nil }
        return try? await AudioFileResource(named: file, configuration: .init(shouldLoop: loops))
    }
}
