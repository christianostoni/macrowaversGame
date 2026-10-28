import SwiftUI

/// Launch window, the story's first screen: a lone Start button floating in the room (plain window, no glass).
/// Start opens the immersive space, where the story goes on (`StoryStep.scroll`); this window closes, so it
/// can never overlap the island, the dragon or the fruit: from then on the words are panels inside the space. It
/// closes only once the space has built its world: meanwhile the dragon tangles and untangles in place of Start
/// (`DragonLoadingView`). The window comes back when the space closes (the Digital Crown, or the story's end).
/// Handing over to the ride, the app has no scene open for a moment and visionOS brings this window back on its
/// own: it steps aside again as soon as the ride's space is open, or its loading animation would float in
/// chapter II.
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
                    DragonLoadingView()
                    Text("Loading…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(24)
        // A space is open and its world built (or the story already went on to the ride): the window steps aside,
        // also when it appears then (brought back by the system).
        .onChange(of: isInTheWay, initial: true) { _, isInTheWay in
            if isInTheWay { dismissWindow(id: Self.windowID) }
        }
        #if DEBUG
        .task {
            if StoryViewModel.startsAtRide && story.step == .start { await start() }
        }
        #endif
    }

    /// The game goes on in an open space: this window has nothing to show.
    private var isInTheWay: Bool {
        viewModel.immersiveSpaceState == .open && (viewModel.isWorldLoaded || story.step.isFullyImmersed)
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
