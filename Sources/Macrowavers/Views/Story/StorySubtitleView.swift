import RealityKit
import SwiftUI

/// The narrator's subtitles (a RealityView attachment): a little below the player's gaze, following it lazily
/// (`GazeFollow`, placed by `StorySubtitleSystem`), facing them. Hidden in SwiftUI when the narrator is silent, never
/// by disabling its entity (see DragonImmersiveView).
struct StorySubtitleView: View {
    static let attachmentID = "StorySubtitle"

    let scroll: StoryScroll

    var body: some View {
        ZStack {
            if let subtitle = scroll.subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    // Its full height: wrapped on two lines, the background covers both.
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    // Dark enough over the scroll's own writing.
                    .background(.black.opacity(0.65), in: .rect(cornerRadius: 18))
                    .id(subtitle)
                    .transition(.opacity)
                    .accessibilityLabel("Narrator: \(subtitle)")
            }
        }
        .frame(width: 720)
        .animation(.easeInOut(duration: 0.3), value: scroll.subtitle)
    }
}

/// The subtitles' place: `GazeFollow` from the tracked eyes.
struct StorySubtitleComponent: Component {
    let viewer: ViewerTracker
    var follow = GazeFollow()
}

struct StorySubtitleSystem: System {
    static let query = EntityQuery(where: .has(StorySubtitleComponent.self))

    init(scene: RealityKit.Scene) {}

    @MainActor
    static func registerAll() {
        StorySubtitleComponent.registerComponent()
        registerSystem()
    }

    func update(context: SceneUpdateContext) {
        let deltaTime = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var state = entity.components[StorySubtitleComponent.self] else { continue }
            let eyes = state.viewer.viewerPose()
            let direction = state.follow.update(forward: eyes.forward, deltaTime: deltaTime)
            entity.setPosition(eyes.position + direction * GazeFollow.distance, relativeTo: nil)
            entity.components.set(state)
        }
    }
}
