import Foundation
import Testing
@testable import Macrowavers

/// The story's narration (`StoryNarration`): its subtitles follow the voice from the first word to the last, in words
/// every player knows, and the paper follows the voice to the painting.
struct StoryNarrationTests {
    @Test func theCuesFollowTheVoice() throws {
        let cues = StoryNarration.cues
        #expect(cues.first?.start == 0)
        #expect(zip(cues, cues.dropFirst()).allSatisfy { $0.start < $1.start })
        #expect((cues.last?.start ?? .infinity) < StoryNarration.duration)
        #expect(StoryNarration.subtitle(at: -1) == nil)
        #expect(StoryNarration.subtitle(at: 0) == "Once there was, once there was not.")
        #expect(StoryNarration.subtitle(at: 21)?.hasPrefix("He could not take the fruit") == true)
        #expect(StoryNarration.subtitle(at: 51) == "The tree remembers you.")
        // The last words stay a moment after the voice, then go.
        #expect(StoryNarration.subtitle(at: StoryNarration.duration + 1) == cues.last?.text)
        #expect(StoryNarration.subtitle(at: StoryNarration.duration + StoryNarration.lastCueHold) == nil)
    }

    /// A king, not a Shah; a demon, not the Black Div: words not every player knows.
    @Test func theSubtitlesUseWordsEveryPlayerKnows() {
        let text = StoryNarration.cues.map(\.text).joined(separator: " ")
        #expect(text.contains("king") && text.contains("demon"))
        #expect(!text.contains("Shah") && !text.contains("Div"))
        #expect(StoryNarration.cues.contains { $0.start == StoryNarration.paintingTime && $0.text == "The tree remembers you." })
    }

    @Test func thePaperReachesThePaintingWithTheVoice() {
        #expect(StoryNarration.pageProgress(at: 0) == 0)
        #expect(StoryNarration.pageProgress(at: StoryNarration.scrollStartTime) == 0)
        #expect(StoryNarration.pageProgress(at: StoryNarration.paintingTime) == 1)
        let samples = stride(from: 0.0, through: StoryNarration.duration, by: 0.5).map(StoryNarration.pageProgress(at:))
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
    }
}
