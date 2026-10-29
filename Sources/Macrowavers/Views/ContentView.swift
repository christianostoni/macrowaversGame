import SwiftUI

/// Launch window, the story's first screen: the game's name written on (`ToranjTitleView`) over a lone Start button,
/// floating in the room (plain window, no glass).
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
    private static let titleHeight: CGFloat = 200
    private static let titleWidth = titleHeight * ToranjTitleView.viewBox.width / ToranjTitleView.viewBox.height

    @Environment(UntangleViewModel.self) private var viewModel
    @Environment(StoryViewModel.self) private var story
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if viewModel.immersiveSpaceState == .closed {
                VStack(spacing: 16) {
                    ToranjTitleView()
                        .frame(height: Self.titleHeight)
                        .padding(.bottom, 12)
                    // As wide as the name above it.
                    Button {
                        Task { await start() }
                    } label: {
                        Text("Start")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .frame(width: Self.titleWidth)
                    .ringLight()
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

/// A ring light around Start's capsule, in the colours of the game's name (`ToranjTitleView`: orange, rose, the
/// leaf's green): dim and still, it lights up and its colours go round the edge while the player looks at the
/// button. Where the eyes are is private, so the system runs it (hover effects, grouped with the button's own);
/// with Reduce Motion it only lights up.
private struct RingLight: ViewModifier {
    private static let colors = [
        // Mostly the fruit's oranges, a touch of the dots' rose and the leaf's green.
        Color(red: 1, green: 0.69, blue: 0.41), // light orange
        Color(red: 1, green: 0.43, blue: 0), // orange
        Color(red: 0.88, green: 0.32, blue: 0.49).opacity(0.7), // rose
        Color(red: 1, green: 0.43, blue: 0),
        Color(red: 0.80, green: 0.88, blue: 0.32).opacity(0.6), // leaf green
        Color(red: 1, green: 0.69, blue: 0.41),
    ]
    /// Once round every 8 s while looked at: a long animation, far longer than any look.
    private static let laps = 60.0
    private static let lapDuration = 8.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    ZStack {
                        // The glow: a soft blurred band, only while looked at.
                        ring(in: proxy.size, lineWidth: 6)
                            .blur(radius: 6)
                            .hoverEffect { effect, isActive, _ in
                                effect.animation(.easeInOut(duration: 0.4)) { $0.opacity(isActive ? 0.55 : 0) }
                            }
                        ring(in: proxy.size, lineWidth: 1.5)
                            .hoverEffect { effect, isActive, _ in
                                effect.animation(.easeInOut(duration: 0.4)) { $0.opacity(isActive ? 0.85 : 0.35) }
                            }
                    }
                }
                .allowsHitTesting(false)
            }
            .hoverEffectGroup()
    }

    /// The colours on a square wide enough to cover the capsule whichever way it turns, seen through its edge.
    private func ring(in size: CGSize, lineWidth: CGFloat) -> some View {
        let side = hypot(size.width, size.height)
        return AngularGradient(colors: Self.colors, center: .center)
            .frame(width: side, height: side)
            .hoverEffect { effect, isActive, _ in
                effect.animation(isActive ? .linear(duration: Self.laps * Self.lapDuration) : .easeOut(duration: 0.6)) {
                    $0.rotationEffect(.degrees(isActive && !reduceMotion ? Self.laps * 360 : 0))
                }
            }
            .frame(width: size.width, height: size.height)
            .mask { Capsule().stroke(lineWidth: lineWidth) }
    }
}

private extension View {
    func ringLight() -> some View { modifier(RingLight()) }
}

#Preview(windowStyle: .plain) {
    ContentView()
        .environment(UntangleViewModel())
        .environment(StoryViewModel())
}
