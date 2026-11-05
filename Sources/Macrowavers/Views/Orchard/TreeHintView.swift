import SwiftUI

/// What to do once the island appears (`StoryStep.adventure`): pick a fruit from the tree, for the elixir's
/// ingredients. A RealityView attachment a little below the player's gaze, following it lazily like the subtitles
/// (`StorySubtitleComponent`), facing them: wherever they look, it is there, never over the tree. It stays until
/// the first ingredient joins the orbit, then the orbit's label counts the rest (`ElixirPanelView`); while a fruit
/// is close, its own panel speaks. Hidden in SwiftUI, never by disabling its entity (see DragonImmersiveView).
struct TreeHintView: View {
    static let attachmentID = "TreeHint"

    @Environment(StoryViewModel.self) private var story
    @Environment(OrchardViewModel.self) private var orchard

    private var isShown: Bool {
        story.step == .adventure && orchard.focusedFruitID == nil
            && orchard.elixirState == .gathering && orchard.orbitingCount == 0
    }

    var body: some View {
        ZStack {
            if isShown {
                VStack(spacing: 10) {
                    Image(systemName: "hand.pinch.fill")
                        .font(.largeTitle)
                    Text("Look at a fruit on the tree and pinch to pick it")
                        .font(.title3.bold())
                    Text("Every fruit hides an ingredient. Find three to brew the elixir that soothes the dragon.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(width: 560)
                .padding(24)
                .glassBackgroundEffect()
                .transition(.opacity)
                .accessibilityElement(children: .combine)
            }
        }
        // The pinch is for the fruit behind it.
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.5), value: isShown)
    }
}

#Preview {
    TreeHintView()
        .environment(StoryViewModel())
        .environment(OrchardViewModel())
}
