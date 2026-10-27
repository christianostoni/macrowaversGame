import SwiftUI

/// Under the story's scroll (a RealityView attachment, placed by `ScrollSystem`): what to do with it, then the way
/// on once the painting is in sight. The story can be skipped at any time. Hidden in SwiftUI, never by disabling
/// its entity (see DragonImmersiveView).
struct ScrollHintView: View {
    static let attachmentID = "ScrollHint"

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
        ZStack {
            if let hint {
                VStack(spacing: 18) {
                    switch hint {
                    case .open:
                        Label("Pull the scroll down to open it", systemImage: "hand.draw")
                            .foregroundStyle(.white.opacity(0.75))
                    case .read:
                        Label("Drag the paper up to read the story", systemImage: "hand.point.up.left")
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
                .shadow(color: .black.opacity(0.6), radius: 8)
                .padding(24)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: hint)
    }
}
