import Foundation

/// The story's English narration (`StoryNarration.m4a`: an ElevenLabs voice, Eleven Multilingual v2, made in Pika's
/// Speech Studio; source in `Assets/Audio/story_narration.mp3`) and its subtitles, the scroll's story in English.
///
/// One cue a sentence (the long one in two), starting when the voice does. The times are the pauses in the
/// recording: its 29 spoken phrases match the story's 29 clauses one for one. A new recording needs new times.
enum StoryNarration {
    struct Cue: Equatable {
        /// Seconds into the narration.
        let start: TimeInterval
        let text: String
    }

    static let fileName = "StoryNarration"
    /// Length of the recording (s).
    static let duration: TimeInterval = 58.83
    /// The last subtitle stays this long after the voice ends (s).
    static let lastCueHold: TimeInterval = 1.5

    static let cues: [Cue] = [
        Cue(start: 0, text: "Once there was, once there was not."),
        Cue(start: 3.16, text: "Long ago, a Shah planted a tree on an island floating between earth and sky."),
        Cue(start: 7.97, text: "Its fruit held the light of fallen stars, and only royal hands could pick it."),
        Cue(start: 13.04, text: "To guard it, the Shah called on an old friend: a dragon of the sky."),
        Cue(start: 17.74, text: "But the Black Div wanted that light."),
        Cue(start: 19.78, text: "He could not take the fruit, so he cursed its guardian:"),
        Cue(start: 22.73, text: "“Circle the tree forever, guard it forever, and never touch a single fruit.”"),
        Cue(start: 27.72, text: "He left his worms inside the fruit, then hunted the Shah’s family until the world forgot them."),
        Cue(start: 33.35, text: "With every circle, the dragon’s body knots tighter, and its heart grows angrier."),
        Cue(start: 38.55, text: "Only an elixir brewed from the tree’s own fruit can soften the curse,"),
        Cue(start: 42.23, text: "and only patient hands can untie what it has knotted."),
        Cue(start: 45.41, text: "But no royal hands were left to pick the fruit."),
        Cue(start: 48.83, text: "So the Div believed."),
        Cue(start: 50.67, text: "One child of the Shah’s line survived, and never knew it."),
        Cue(start: 54.45, text: "The tree remembers you."),
        Cue(start: 56.25, text: "Patience is bitter, but its fruit is sweet."),
    ]

    /// When the narrator says "The tree remembers you": the painting is in the window by then.
    static let paintingTime: TimeInterval = 54.45
    /// The paper starts moving with the voice once the first sentences, at the top of the page, have been said (s).
    static let scrollStartTime: TimeInterval = 7

    /// What the narrator is saying `time` s into the narration (nil before it and once it has ended).
    static func subtitle(at time: TimeInterval) -> String? {
        guard time >= 0, time < duration + lastCueHold else { return nil }
        return cues.last { $0.start <= time }?.text
    }

    /// How far down the page (0…1) the paper should be `time` s into the narration, for the painting to come into
    /// the window as the narrator gets to it.
    static func pageProgress(at time: TimeInterval) -> Float {
        Float(min(max((time - scrollStartTime) / (paintingTime - scrollStartTime), 0), 1))
    }
}
