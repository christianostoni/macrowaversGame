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
    /// The story's last pages show in the launch window, back in the room: the ride's panel leaves them out, so they
    /// never float in the sky as its space closes.
    var showsLastPages = true

    var body: some View {
        ZStack {
            if let page = story.step.page, showsLastPages || !story.step.isLastPages {
                StoryPageView(page: page, isChapter: Self.isChapterStyled(story.step)) {
                    story.advance()
                }
                .id(story.step)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: story.step)
    }

    /// Chapter pages, and the promise of the next one, name it in spaced gold capitals.
    static func isChapterStyled(_ step: StoryStep) -> Bool {
        step == .chapter || step == .secondChapter || step == .toBeContinued
    }
}

/// One page, tapped to go on (look at it and pinch): a question's answer is its hint, where the others say "Tap to
/// continue".
private struct StoryPageView: View {
    let page: StoryStep.Page
    let isChapter: Bool
    let advance: () -> Void

    var body: some View {
        Button(action: advance) {
            StoryPageCard(page: page, isChapter: isChapter) {
                Label(hint, systemImage: "hand.tap")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
        .contentShape(.hoverEffect, .rect(cornerRadius: StoryPageCardStyle.cornerRadius))
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
}

/// A page's look, after the design team's Lotus UI kit ("clear glass, no tint"): clear glass in their tile frame,
/// 720 × 200 pt in `ChapterPanelFrame`. A chapter's page names it in spaced gold capitals over its proverb; the
/// others have a serif title over their lines, in italic. Under the words, `footer`: the page's hint, or the ride's
/// loading animation under chapter II's name (`DragonRideView`).
struct StoryPageCard<Footer: View>: View {
    let page: StoryStep.Page
    let isChapter: Bool
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(spacing: 8) {
            words
            footer
                .padding(.top, 2)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 48)
        .frame(width: StoryPageCardStyle.size.width, height: StoryPageCardStyle.size.height)
        .contentShape(.rect(cornerRadius: StoryPageCardStyle.cornerRadius))
        .glassBackgroundEffect(in: .rect(cornerRadius: StoryPageCardStyle.cornerRadius))
        .overlay {
            Image("ChapterPanelFrame")
                .resizable()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var words: some View {
        VStack(spacing: 8) {
            // A page without a title is its lines alone.
            if !page.title.isEmpty {
                if isChapter {
                    Text(page.title.uppercased())
                        .font(.system(size: 13, design: .serif))
                        .tracking(4.4)
                        .foregroundStyle(StoryPageCardStyle.gold)
                } else {
                    Text(page.title)
                        .font(.system(size: 30, design: .serif))
                        .foregroundStyle(.white)
                }
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

/// `StoryPageCard`'s measures and colour (a generic type cannot store its own).
enum StoryPageCardStyle {
    static let size = CGSize(width: 720, height: 200)
    static let cornerRadius: CGFloat = 60
    /// The kit's gold for the chapter's name over clear glass (#f2cf86).
    static let gold = Color(red: 0.95, green: 0.81, blue: 0.53)
}

#Preview {
    StoryPanelView()
        .environment(StoryViewModel())
}
