import SwiftUI

/// The story's words inside the immersive space (a RealityView attachment): the narrator's pages in front of
/// the player, the dragon's above its body (`StoryPanelSystem` places it). The room is darkened around them
/// (`StoryStep.dimsSurroundings`, applied by the immersive view).
/// Between pages, and during the game, it is hidden in SwiftUI, never by disabling its entity (see
/// DragonImmersiveView).
struct StoryPanelView: View {
    static let attachmentID = "StoryPanel"

    @Environment(StoryViewModel.self) private var story
    /// Pages on a glass panel, legible over a bright sky (the ride); without it, white words over the darkened room.
    var hasBackdrop = false

    var body: some View {
        ZStack {
            if let page = story.step.page {
                StoryPageView(page: page) { story.advance() }
                    .glassBackgroundEffect(displayMode: hasBackdrop ? .always : .never)
                    .id(story.step)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: story.step)
    }
}

/// One page: a bold title and its lines, white over the darkened room, as in the wireframes.
/// A narrator's page is one big button (look at it and pinch to go on); a question has its own answer button.
private struct StoryPageView: View {
    let page: StoryStep.Page
    let advance: () -> Void

    private static let cornerRadius: CGFloat = 32

    var body: some View {
        switch page.advance {
        case .tap:
            Button(action: advance) {
                VStack(spacing: 24) {
                    words
                    Label("Tap to continue", systemImage: "hand.tap")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(32)
                .contentShape(.rect(cornerRadius: Self.cornerRadius))
            }
            .buttonStyle(.plain)
            .contentShape(.hoverEffect, .rect(cornerRadius: Self.cornerRadius))
            .hoverEffect(.highlight)
            .accessibilityHint("Continues the story")
        case .answer(let answer):
            VStack(spacing: 24) {
                words
                Button(answer, action: advance)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(32)
        }
    }

    private var words: some View {
        VStack(spacing: 12) {
            Text(page.title)
                .font(.title.bold())
                .foregroundStyle(.white)
            ForEach(page.lines, id: \.self) { line in
                Text(line)
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.85))
            }
            // The dragon's words end with a thin rule, as in the wireframes.
            if page.anchor == .dragon {
                Rectangle()
                    .fill(.white.opacity(0.3))
                    .frame(width: 420, height: 1)
                    .padding(.top, 8)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 640)
        // Legible over any room, however bright.
        .shadow(color: .black.opacity(0.6), radius: 8)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    StoryPanelView()
        .environment(StoryViewModel())
}
