import Foundation
import Testing
@testable import Macrowavers

@MainActor
struct GameSettingsTests {
    /// Defaults of their own, emptied after each test: the app's are never touched.
    private let suiteName = "GameSettingsTests-\(UUID().uuidString)"

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let defaults = UserDefaults(suiteName: suiteName)!
        body(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func aFirstLaunchHasMusicAndVoiceAndHandGestures() {
        withDefaults { defaults in
            let settings = GameSettings(defaults: defaults)
            #expect(settings.isMusicOn)
            #expect(settings.isNarratorVoiceOn)
            #expect(!settings.playsWithTaps)
        }
    }

    @Test func theSettingsAreTheSameAtTheNextLaunch() {
        withDefaults { defaults in
            let settings = GameSettings(defaults: defaults)
            settings.isMusicOn = false
            settings.isNarratorVoiceOn = false
            settings.playsWithTaps = true

            let nextLaunch = GameSettings(defaults: defaults)
            #expect(!nextLaunch.isMusicOn)
            #expect(!nextLaunch.isNarratorVoiceOn)
            #expect(nextLaunch.playsWithTaps)
        }
    }

    @Test func turnedBackOnTheyStayOn() {
        withDefaults { defaults in
            let settings = GameSettings(defaults: defaults)
            settings.isMusicOn = false
            settings.isMusicOn = true
            #expect(GameSettings(defaults: defaults).isMusicOn)
        }
    }
}
