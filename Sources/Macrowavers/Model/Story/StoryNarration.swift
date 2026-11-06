import Foundation

/// The story's English narration (`StoryNarration.m4a`: an ElevenLabs voice, Eleven Multilingual v2, made in Pika's
/// Speech Studio; source in `Assets/Audio/story_narration.mp3`) and its subtitles, the scroll's story in English.
///
/// One cue a sentence (the long one in two), starting when the voice does: the times are where each sentence starts
/// after a pause in the recording. A new recording needs new times.
enum StoryNarration {
    struct Cue: Equatable {
        /// Seconds into the narration.
        let start: TimeInterval
        let text: String
    }

    static let fileName = "StoryNarration"
    /// Length of the recording (s).
    static let duration: TimeInterval = 54.70
    /// The last subtitle stays this long after the voice ends (s).
    static let lastCueHold: TimeInterval = 1.5

    static let cues: [Cue] = [
        Cue(start: 0, text: "Once there was, once there was not."),
        Cue(start: 2.96, text: "Long ago, a king planted a tree on an island floating between earth and sky."),
        Cue(start: 8.21, text: "Its fruit held the light of fallen stars. And curative powers."),
        Cue(start: 13.49, text: "To guard it, the king called on an old friend: a dragon of the sky."),
        Cue(start: 18.30, text: "But a demon wanted that light."),
        Cue(start: 20.25, text: "He could not take the fruits, so he put a curse on the dragon:"),
        Cue(start: 23.51, text: "“Circle the tree forever, if you leave it you will not be able to move.”"),
        Cue(start: 27.65, text: "He hunted the king’s family until the world forgot them."),
        Cue(start: 31.09, text: "If the dragon leaves, its body knots tighter, and its heart grows angrier."),
        Cue(start: 36.28, text: "Only an elixir brewed from the tree’s own fruit can soften the curse,"),
        Cue(start: 40.02, text: "and only patient hands can untie what it has knotted."),
        Cue(start: 43.74, text: "The demon believed no hands were left to pick the fruit."),
        Cue(start: 47.30, text: "But one child of the king’s line survived, and never knew it."),
        Cue(start: 50.60, text: "The tree remembers you."),
        Cue(start: 52.16, text: "Patience is bitter, but its fruit is sweet."),
    ]

    /// When the narrator says "The tree remembers you": the painting is in the window by then.
    static let paintingTime: TimeInterval = 50.60
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
