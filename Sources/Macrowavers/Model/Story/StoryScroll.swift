import Foundation
import Observation

/// The story's scroll (`StoryStep.scroll`), as the player handles it: it appears closed in front of them; they
/// pull it open (or tap it), drag the paper up to read the story down to its painting, then go on (or skip it):
/// it rolls up, fades away, and the story moves on (`isDone`).
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
            let travel = roll.travel(window: roll.openWindow)
            scroll = min(max(start.scroll + moved / max(travel, 0.01), 0), 1)
            if scroll >= Self.endThreshold { hasReachedEnd = true }
        }
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
    }

    /// Opens, closes and fades, a frame at a time.
    func update(deltaTime: Float) {
        switch phase {
        case .hidden, .done:
            return
        case .closed, .reading:
            fade = min(1, fade + deltaTime / Self.fadeDuration)
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
}
