import SwiftUI

/// Scene hierarchy: one launch window and one immersive space, never visible together.
/// - launch window: opens the island, then closes so it never overlaps the 3D content;
/// - immersive space (.mixed) with the island, its fruit and the dragon. Its controls are panels inside the
///   space (island panel on the left, dragon panel on the right), placed outside the play area.
/// Closing the space (Restart Game or Digital Crown) brings the launch window back.
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

        ImmersiveSpace(id: DragonImmersiveView.spaceID) {
            DragonImmersiveView()
                .environment(untangleViewModel)
                .environment(orchardViewModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
