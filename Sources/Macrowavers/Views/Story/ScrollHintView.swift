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
                                .foregroundStyle(.secondary)
                        case .read:
                            Label("Drag the paper to read at your own pace", systemImage: "hand.point.up.left")
                                .foregroundStyle(.secondary)
                        case .carryOn:
                            // Like Start: a glass capsule as wide, with the name's ring light.
                            Button {
                                scroll.finish()
                            } label: {
                                Text("Continue")
                                    .frame(maxWidth: .infinity)
                                    .ringLight(aroundButtonOf: .large)
                            }
                            .buttonBorderShape(.capsule)
                            .controlSize(.large)
                            .frame(width: ContentView.titleWidth)
                        }
                        if hint != .carryOn {
                            // The same, smaller and quieter: it is not the way on.
                            Button { scroll.finish() } label: {
                                Text("Skip the story")
                                    .ringLight(aroundButtonOf: .small)
                            }
                            .font(.callout.weight(.medium))
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                        }
                    }
                    .font(.title3.weight(.medium))
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: hint)
        }
        .shadow(color: .black.opacity(0.6), radius: 8)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
    }
}
