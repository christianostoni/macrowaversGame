import Foundation
import Observation

/// The story's scroll (`StoryStep.scroll`), as the player handles it: it appears closed in front of them; they
/// pull it open (or tap it), drag the paper up to read the story down to its painting, then go on (or skip it):
/// it rolls up, fades away, and the story moves on (`isDone`).
/// Opened, the narrator tells the story in English (`StoryNarration`, with its subtitles) and the paper moves with
/// the voice, the painting coming into the window as the narrator gets to it, until the player drags it.
/// Its shape is a `ScrollRoll`, set once the page is loaded (its proportions come from the page's image).
@MainActor
@Observable
final class StoryScroll {
    enum Phase: Equatable {
        /// Not in the room.
        case hidden
        /// Closed in front of the player, waiting to be opened.
        case closed
        /// Open (or opening): the paper can be read.
        case reading
        /// Rolling up and fading away.
        case closing
        /// Gone: the story goes on.
        case done
    }

    private(set) var phase = Phase.hidden
    /// 0 closed … 1 open.
    private(set) var open: Float = 0
    /// 0 the window on the page's top … 1 on its end.
    private(set) var scroll: Float = 0
    /// Opacity: it fades in when it appears and out when it is done.
    private(set) var fade: Float = 0
    /// The player has reached the painting at the page's end.
    private(set) var hasReachedEnd = false
    /// The player holds it (the scroll does not glide back in front of them meanwhile).
    var isDragged: Bool { dragStart != nil }
    /// The narration is playing: from the scroll's opening until it ends or the scroll rolls up.
    private(set) var isNarrating = false
    /// What the narrator is saying (nil: nothing).
    private(set) var subtitle: String?
    /// Seconds into the narration (nil: not started). Not observed: it changes every frame, `subtitle` with it.
    @ObservationIgnored private var narrationTime: TimeInterval?
    /// The paper moves with the voice until the player drags it.
    @ObservationIgnored private var followsNarration = true

    /// The scroll's shape (nil until the page is loaded: it cannot be opened yet).
    var roll: ScrollRoll?

    var pose: ScrollRoll.Pose? { roll?.pose(open: open, scroll: scroll) }
    var isDone: Bool { phase == .done }

    /// Pulled open past this (0…1) when the hand lets go, it opens all the way; otherwise it closes again.
    static let openThreshold: Float = 0.3
    /// Scrolled this far (0…1), the painting is in the window.
    static let endThreshold: Float = 0.97
    /// Opening, closing (1/s: the gap closes by ~95% in 1/rate s) and fading (s).
    static let openRate: Float = 4
    static let closeRate: Float = 3
    static let fadeDuration: Float = 0.6

    /// Where the hand was (scene height, m) and the scroll's `open` and `scroll` when the drag started.
    private struct DragStart {
        let height: Float
        let open: Float
        let scroll: Float
    }

    private var dragStart: DragStart?
    /// Opening or closing on its own, towards this.
    private var openTarget: Float?

    /// The story reaches the scroll: it appears, closed.
    func present() {
        phase = .closed
        open = 0
        scroll = 0
        fade = 0
        hasReachedEnd = false
        dragStart = nil
        openTarget = nil
        isNarrating = false
        subtitle = nil
        narrationTime = nil
        followsNarration = true
    }

    /// The story left it (the space closed): gone at once.
    func reset() {
        present()
        phase = .hidden
    }

    /// Pinch on the closed scroll: it opens.
    func tap() {
        guard phase == .closed, roll != nil else { return }
        phase = .reading
        openTarget = 1
    }

    /// The hand holding the scroll is at this height (scene, m). Closed, pulling down opens it; open, the paper
    /// follows the hand up and down through the window.
    func drag(height: Float) {
        guard let roll, phase == .closed || phase == .reading else { return }
        let start = dragStart ?? DragStart(height: height, open: open, scroll: scroll)
        dragStart = start
        let moved = height - start.height
        if phase == .closed || open < 1 {
            openTarget = nil
            open = min(max(start.open - moved / max(roll.openWindow - roll.closedWindow, 0.01), 0), 1)
        } else {
            followsNarration = false
            let travel = roll.travel(window: roll.openWindow)
            scrollPaper(to: start.scroll + moved / max(travel, 0.01))
        }
    }

    private func scrollPaper(to position: Float) {
        scroll = min(max(position, 0), 1)
        if scroll >= Self.endThreshold { hasReachedEnd = true }
    }

    /// The hand lets go: half open, it opens all the way (or closes again).
    func endDrag() {
        dragStart = nil
        guard phase == .closed || (phase == .reading && open < 1) else { return }
        if open >= Self.openThreshold {
            phase = .reading
            openTarget = 1
        } else {
            phase = .closed
            openTarget = 0
        }
    }

    /// The player has read it (or skips it): it rolls up and fades away.
    func finish() {
        guard phase == .closed || phase == .reading else { return }
        phase = .closing
        dragStart = nil
        openTarget = 0
        isNarrating = false
        subtitle = nil
    }

    /// Opens, closes and fades, a frame at a time.
    func update(deltaTime: Float) {
        switch phase {
        case .hidden, .done:
            return
        case .closed:
            fade = min(1, fade + deltaTime / Self.fadeDuration)
        case .reading:
            fade = min(1, fade + deltaTime / Self.fadeDuration)
            narrate(deltaTime: deltaTime)
        case .closing:
            // Rolled up, it fades away.
            if open < 0.02 { fade = max(0, fade - deltaTime / Self.fadeDuration) }
            if fade == 0 { phase = .done }
        }
        guard let target = openTarget else { return }
        let rate = target > open ? Self.openRate : Self.closeRate
        open += (target - open) * (1 - exp(-deltaTime * rate))
        if abs(target - open) < 0.002 {
            open = target
            openTarget = nil
        }
    }

    /// The narration goes on (it starts with the scroll's opening): its subtitle, and the paper following the voice
    /// once the scroll is open, only ever forwards.
    private func narrate(deltaTime: Float) {
        let time = narrationTime.map { $0 + TimeInterval(deltaTime) } ?? 0
        if narrationTime == nil { isNarrating = true }
        narrationTime = time
        let said = StoryNarration.subtitle(at: time)
        if said != subtitle { subtitle = said }
        if isNarrating && time >= StoryNarration.duration { isNarrating = false }
        guard followsNarration, open == 1, dragStart == nil else { return }
        let progress = StoryNarration.pageProgress(at: time)
        if progress > scroll { scrollPaper(to: progress) }
    }
}
