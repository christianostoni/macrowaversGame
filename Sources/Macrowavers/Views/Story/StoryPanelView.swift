import SwiftUI

/// The story's words inside the immersive space (a RealityView attachment): the narrator's pages in front of
/// the player, the dragon's above its body (`StoryPanelSystem` places it). The room is darkened around them
/// (`StoryStep.dimsSurroundings`, applied by the immersive view).
/// Between pages, and during the game, it is hidden in SwiftUI, never by disabling its entity (see
/// DragonImmersiveView).
struct StoryPanelView: View {
    static let attachmentID = "StoryPanel"

    @Environment(StoryViewModel.self) private var story
    /// Asked for by the ride, over its bright sky. Every page now has its own framed glass (`StoryPageView`),
    /// in the room as in the sky, so it changes nothing; it stays until `DragonRideView` stops passing it.
    var hasBackdrop = false

    var body: some View {
        ZStack {
            if let page = story.step.page {
                StoryPageView(page: page, isChapter: story.step == .chapter || story.step == .secondChapter) {
                    story.advance()
                }
                .id(story.step)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: story.step)
    }
}

/// One page, after the design team's Lotus UI kit ("clear glass, no tint"): clear glass in their tile frame.
/// A chapter's page names it in spaced gold capitals over its proverb; the others have a serif title over their
/// lines, in italic. Every page, 720 × 200 pt in `ChapterPanelFrame`, is one big button (look at it and pinch
/// to go on); a question's answer is its hint, where the others say "Tap to continue".
private struct StoryPageView: View {
    let page: StoryStep.Page
    let isChapter: Bool
    let advance: () -> Void

    private static let size = CGSize(width: 720, height: 200)
    private static let cornerRadius: CGFloat = 60
    /// The kit's gold for the chapter's name over clear glass (#f2cf86).
    private static let gold = Color(red: 0.95, green: 0.81, blue: 0.53)

    var body: some View {
        Button(action: advance) {
            VStack(spacing: 8) {
                words
                Label(hint, systemImage: "hand.tap")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 2)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 48)
            .frame(width: Self.size.width, height: Self.size.height)
            .contentShape(.rect(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(.plain)
        .glassBackgroundEffect(in: .rect(cornerRadius: Self.cornerRadius))
        .overlay {
            Image("ChapterPanelFrame")
                .resizable()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .contentShape(.hoverEffect, .rect(cornerRadius: Self.cornerRadius))
        .hoverEffect(.highlight)
        .accessibilityHint("Continues the story")
    }

    /// What tapping the page does: go on, or the page's own answer to its question.
    private var hint: String {
        switch page.advance {
        case .tap: "Tap to continue"
        case .answer(let answer): answer
        }
    }

    private var words: some View {
        VStack(spacing: 8) {
            if isChapter {
                Text(page.title.uppercased())
                    .font(.system(size: 13, design: .serif))
                    .tracking(4.4)
                    .foregroundStyle(Self.gold)
            } else {
                Text(page.title)
                    .font(.system(size: 30, design: .serif))
                    .foregroundStyle(.white)
            }
            VStack(spacing: 2) {
                ForEach(page.lines, id: \.self) { line in
                    Text(line)
                        // One line, a proverb, is bigger than a page of two.
                        .font(.system(size: page.lines.count > 1 ? 26 : 30, weight: .semibold, design: .serif)
                            .italic())
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            }
        }
        // Legible over any room, however bright.
        .shadow(color: .black.opacity(0.45), radius: 5, y: 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    StoryPanelView()
        .environment(StoryViewModel())
}
