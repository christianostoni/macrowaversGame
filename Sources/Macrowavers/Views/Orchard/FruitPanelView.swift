import SwiftUI

/// The words under the fruit in front of the player (a RealityView attachment, not a window): what to do now, how to
/// turn the fruit, how many worms are caught. A story page to read (`StoryPageCard`'s clear glass in the tile frame,
/// serif words), with nothing to press: a fruit goes back to the tree by itself, once its ingredient is out, once it
/// is found empty, or, its gem not needed (the three already found), once the player has finished it
/// (`OrchardViewModel.emptyReturnDelay` after). A fruit not needed says so in the page's title.
struct FruitPanelView: View {
    static let attachmentID = "FruitPanel"

    @Environment(OrchardViewModel.self) private var orchard

    var body: some View {
        // Hidden in SwiftUI, not by disabling its entity (see DragonImmersiveView).
        ZStack {
            if orchard.focusedFruitID != nil {
                card
                    .id(title + hint)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: title + hint)
    }

    /// Big, above the hint, only for a fruit not needed: the notice can't pass for the usual instructions.
    private var title: String {
        orchard.isFocusedFruitNotNeeded ? "All three gems found!" : ""
    }

    private var isEmpty: Bool { orchard.isFocusedFruitEmpty && orchard.isFocusedFruitExplored }

    /// Drawn as a story page (`StoryPageCard`): the hint in its italic lines, one or two, at the story's one size; under
    /// it, like the story's "Tap to continue", the worms caught or how to turn the fruit.
    private var card: some View {
        StoryPageCard(page: StoryStep.Page(title: title, lines: Self.lines(of: hint), anchor: .viewer, advance: .tap),
                      isChapter: false) {
            if let detail {
                Label(detail.text, systemImage: detail.icon)
                    .font(.callout.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.default, value: orchard.caughtWorms)
            }
        }
        .allowsHitTesting(false)
    }

    /// The small line under the hint: the worms caught, or how to turn the fruit with its ring of light (`TurnRing`).
    private var detail: (text: String, icon: String)? {
        if orchard.focusedFruit?.kind == .apple && orchard.focusedOrb == .sealed && orchard.isAppleOpen {
            return ("Worms caught: \(orchard.caughtWorms)/\(orchard.wormCount)", "ant")
        }
        return isEmpty ? nil : ("Pinch the ring of light and slide round it to turn the fruit", "hand.pinch")
    }

    /// A story page's lines are each one line long: a long hint is cut in two, at the sentence's break nearest its
    /// middle (else the space nearest it).
    nonisolated static func lines(of text: String) -> [String] {
        guard text.count > 44 else { return [text] }
        let words = text.split(separator: " ")
        let middle = text.count / 2
        var best: (cut: Int, score: Int)?
        var length = 0
        for index in words.indices.dropLast() {
            length += words[index].count + 1
            let breaks = [".", ":", "!", ","].contains(words[index].last.map(String.init) ?? "")
            let score = abs(length - middle) - (breaks ? 12 : 0)
            if best.map({ score < $0.score }) ?? true { best = (index + 1, score) }
        }
        guard let cut = best?.cut else { return [text] }
        return [words[..<cut].joined(separator: " "), words[cut...].joined(separator: " ")]
    }

    private var hint: String {
        switch orchard.focusedOrb {
        case .revealed:
            return orchard.elixirState == .gathering
                ? "A gem for the elixir!"
                : "You already have three gems: brew the elixir first."
        case .orbiting, .spent:
            return isEmpty ? "You already took this gem. Back to the tree it goes." : openHint
        case .sealed, nil:
            return orchard.isFocusedFruitNotNeeded ? fullFlaskHint : openHint
        }
    }

    /// Under the title of a fruit not needed: how to go on (it can still be played with), then that it goes back.
    private var fullFlaskHint: String {
        if orchard.isFocusedFruitGoingBack { return "This one goes back to the tree." }
        guard orchard.elixirState == .ready else { return "The elixir is brewing." }
        return orchard.isHandTrackingAvailable
            ? "Snap your fingers to brew the elixir."
            : "Tap “Create the Elixir” to brew it."
    }

    /// How to open the focused fruit.
    private var openHint: String {
        switch orchard.focusedFruit?.kind {
        case .apple:
            if !orchard.isAppleOpen { return "Pull to open the apple." }
            return orchard.focusedOrb == .sealed
                ? "Catch the worms! They are sneaky, and get fast."
                : "Only worms in this one."
        case .pomegranate:
            return orchard.pomegranateBurst ? "Drag the seeds around for fun." : "Pull it apart with both hands."
        case .banana:
            return "Pinch a strip and peel the whole banana."
        case .orange:
            return orchard.orangeOpened
                ? "Fresh orange wedges!"
                : "Pull it apart with both hands."
        case .pineapple:
            return orchard.isHandTrackingAvailable
                ? "Chop the pineapple with an open hand."
                : "Tap it to cut it open."
        case nil:
            return ""
        }
    }
}

#Preview {
    FruitPanelView()
        .environment(OrchardViewModel())
}
