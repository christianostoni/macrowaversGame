import SwiftUI

/// What to do once the island appears (`StoryStep.adventure`): pick a fruit from the tree, for the elixir's
/// ingredients. A RealityView attachment a little below the player's gaze, following it lazily like the subtitles
/// (`StorySubtitleComponent`), facing them: wherever they look, it is there, never over the tree. It stays until
/// the first ingredient joins the orbit, then the orbit's label counts the rest (`ElixirPanelView`); while a fruit
/// is close, its own panel speaks. Pinching it closes it for good. Hidden in SwiftUI, never by disabling its entity
/// (see DragonImmersiveView).
struct TreeHintView: View {
    static let attachmentID = "TreeHint"

    @Environment(StoryViewModel.self) private var story
    @Environment(OrchardViewModel.self) private var orchard
    /// The player pinched the page: it is read, it does not come back.
    @State private var isDismissed = false

    private var isShown: Bool {
        !isDismissed && story.step == .adventure && orchard.focusedFruitID == nil
            && orchard.elixirState == .gathering && orchard.orbitingCount == 0
    }

    var body: some View {
        ZStack {
            if isShown {
                // A story page (`StoryPageCard`'s clear glass in the tile frame, serif words); pinching it closes it.
                Button {
                    isDismissed = true
                } label: {
                    page
                }
                .buttonStyle(.plain)
                .contentShape(.hoverEffect, .rect(cornerRadius: StoryPageCardStyle.cornerRadius))
                .hoverEffect(.highlight)
                .transition(.opacity)
                .accessibilityHint("Closes the tip")
            }
        }
        .animation(.easeInOut(duration: 0.5), value: isShown)
    }

    /// Drawn as a story page (`StoryPageCard`): its two lines in italic, no title (gold is for the chapters and the
    /// dragon's thanks), the hint under them like the story's "Tap to continue".
    private var page: some View {
        StoryPageCard(page: Self.words, isChapter: false) {
            Label("Pinch to pick a fruit", systemImage: "hand.pinch")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private static let words = StoryStep.Page(title: "", lines: ["Every fruit hides a gem.",
                                                                 "Find three to create the elixir for the dragon."],
                                              anchor: .viewer, advance: .tap)
}

#Preview {
    TreeHintView()
        .environment(StoryViewModel())
        .environment(OrchardViewModel())
}
