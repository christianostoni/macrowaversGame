import SwiftUI

/// Under the story's scroll (a RealityView attachment, placed by `ScrollSystem`): what to do with the scroll, then
/// the way on once the painting is in sight. The story can be skipped at any time. Hidden in SwiftUI, never by
/// disabling its entity (see DragonImmersiveView). A fixed height, its top under the roll: the words come and go
/// without moving. The narrator's subtitles follow the gaze instead (`StorySubtitleView`).
struct ScrollHintView: View {
    static let attachmentID = "ScrollHint"
    /// Its size (points): the hint and a button.
    static let size = CGSize(width: 900, height: 160)

    let scroll: StoryScroll

    private enum Hint: Equatable {
        case open, read, carryOn
    }

    private var hint: Hint? {
        switch scroll.phase {
        case .closed: .open
        case .reading: scroll.hasReachedEnd ? .carryOn : .read
        case .hidden, .closing, .done: nil
        }
    }

    var body: some View {
        VStack {
            ZStack {
                if let hint {
                    VStack(spacing: 14) {
                        switch hint {
                        case .open:
                            Label("Pull the scroll down to open it", systemImage: "hand.draw")
                                .foregroundStyle(.white.opacity(0.75))
                        case .read:
                            Label("Drag the paper to read at your own pace", systemImage: "hand.point.up.left")
                                .foregroundStyle(.white.opacity(0.75))
                        case .carryOn:
                            Button("Continue") { scroll.finish() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                        }
                        if hint != .carryOn {
                            Button("Skip the story") { scroll.finish() }
                                .buttonStyle(.plain)
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .font(.title3)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: hint)
        }
        .shadow(color: .black.opacity(0.6), radius: 8)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
    }
}
