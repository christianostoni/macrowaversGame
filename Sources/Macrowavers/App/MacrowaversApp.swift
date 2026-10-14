import SwiftUI

/// Scene hierarchy:
/// - main window (island): launch, environment management, restart of the whole game;
/// - dragon panel: single-instance `Window`, opened only by tapping the dragon, never restored at launch;
/// - immersive space (.mixed) with the island, its fruit and the dragon.
/// They all share the same view models; only the main window and the space open and close the others.
@main
struct MacrowaversApp: App {
    @State private var appModel = AppModel()
    /// "Untangle the Dragon" feature (AR126-100): one view model shared by the windows and the immersive space.
    @State private var untangleViewModel = UntangleViewModel()
    /// The tree's fruit and the artifact that soothes the dragon.
    @State private var orchardViewModel = OrchardViewModel()

    init() {
        DragonBodySystem.registerAll()
        OrchardSystem.registerAll()
    }

    var body: some Scene {
        WindowGroup(id: ContentView.windowID) {
            ContentView()
                .environment(appModel)
                .environment(untangleViewModel)
                .environment(orchardViewModel)
        }
        .windowResizability(.contentSize)

        Window("Dragon", id: DragonPanelView.windowID) {
            DragonPanelView()
                .environment(untangleViewModel)
                .environment(orchardViewModel)
        }
        .windowResizability(.contentSize)
        // Opens only from the game: not at app launch and never restored from a previous session.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultWindowPlacement { _, context in
            if let island = context.windows.first(where: { $0.id == ContentView.windowID }) {
                return WindowPlacement(.trailing(island))
            }
            return WindowPlacement()
        }

        ImmersiveSpace(id: DragonImmersiveView.spaceID) {
            DragonImmersiveView()
                .environment(untangleViewModel)
                .environment(orchardViewModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
