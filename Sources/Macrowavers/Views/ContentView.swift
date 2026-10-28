import SwiftUI

/// Launch window, the story's first screen: a lone Start button floating in the room (plain window, no glass).
/// Start opens the immersive space, where the story goes on (`StoryStep.searching`); this window closes, so it
/// can never overlap the island, the dragon or the fruit: from then on the controls are panels inside the space
/// (`IslandControlsView`). It closes only once the space has built its world: meanwhile a spinner turns in place of
/// Start. The window comes back when the space closes (Restart Game or Digital Crown).
/// Under Start, a small menu picks the app icon (`AppIconMenu`).
struct ContentView: View {
    static let windowID = "IslandWindow"

    @Environment(UntangleViewModel.self) private var viewModel
    @Environment(StoryViewModel.self) private var story
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if viewModel.immersiveSpaceState == .closed {
                VStack(spacing: 16) {
                    Button("Start") {
                        Task { await start() }
                    }
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .accessibilityHint("Opens the floating island and begins the story")
                    AppIconMenu()
                        .controlSize(.small)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(24)
        // The world is built (or the story already went on to the ride): the window steps aside.
        .onChange(of: viewModel.isWorldLoaded || story.step.isFullyImmersed) { _, isReady in
            if isReady && viewModel.immersiveSpaceState != .closed { dismissWindow(id: Self.windowID) }
        }
        #if DEBUG
        .task {
            if StoryViewModel.startsAtRide && story.step == .start { await start() }
        }
        #endif
    }

    /// Window and space actions exist only in the Environment: they live in the view.
    private func start() async {
        guard viewModel.immersiveSpaceState == .closed else { return }
        viewModel.immersiveSpaceState = .inTransition
        viewModel.isWorldLoaded = false
        story.begin()
        switch await openImmersiveSpace(id: DragonImmersiveView.spaceID) {
        case .opened:
            #if DEBUG
            // Like in the story: the ride starts in the open space, which then turns fully immersive.
            if StoryViewModel.startsAtRide { story.skipToRide() }
            #endif
            // The state becomes `.open` in DragonImmersiveView's onAppear. The window steps aside once the world
            // is built (see `onChange`), at once if it already is.
            if viewModel.isWorldLoaded { dismissWindow(id: Self.windowID) }
        case .userCancelled, .error:
            viewModel.immersiveSpaceState = .closed
            story.reset()
        @unknown default:
            viewModel.immersiveSpaceState = .closed
            story.reset()
        }
    }
}

#Preview(windowStyle: .plain) {
    ContentView()
        .environment(UntangleViewModel())
        .environment(StoryViewModel())
}
