import Foundation
import Observation

/// The player's settings, changed in the Settings window (`SettingsView`) and kept between launches in the app's own
/// defaults. `UserDefaults` is a "required reason" API: the app's `PrivacyInfo.xcprivacy` declares it (CA92.1, data
/// only the app itself reads).
@MainActor
@Observable
final class GameSettings {
    /// The story's music (`GameMusic`), on the island and on the ride.
    var isMusicOn: Bool {
        didSet { defaults.set(isMusicOn, forKey: Key.music) }
    }
    /// The narrator's voice reading the scroll's story (`StoryNarrator`); its subtitles show either way.
    var isNarratorVoiceOn: Bool {
        didSet { defaults.set(isNarratorVoiceOn, forKey: Key.narratorVoice) }
    }
    /// Taps instead of the gestures read from the hands: the game never asks to track them, and plays as when the
    /// player has not allowed it (a tap chops the pineapple and brews the elixir, the dragon flies itself).
    var playsWithTaps: Bool {
        didSet { defaults.set(playsWithTaps, forKey: Key.playsWithTaps) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let music = "isMusicOn"
        static let narratorVoice = "isNarratorVoiceOn"
        static let playsWithTaps = "playsWithTaps"
    }

    /// `defaults`: the app's own; tests pass theirs.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isMusicOn = defaults.object(forKey: Key.music) as? Bool ?? true
        isNarratorVoiceOn = defaults.object(forKey: Key.narratorVoice) as? Bool ?? true
        playsWithTaps = defaults.bool(forKey: Key.playsWithTaps)
    }
}
