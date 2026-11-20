import SwiftUI

/// Scene hierarchy: one launch window and two immersive spaces, never visible together.
/// - launch window (plain, the story's Start button): opens the island, then closes so it never overlaps the
///   3D content;
/// - Settings window (glass), pushed in the launch window's place by its Settings button: never open with the game,
///   since Start is hidden while it is;
/// - immersive space (.mixed) with the island, its fruit and the dragon. Its words are panels inside the space
///   (RealityView attachments), no window;
/// - immersive space (.full) for the story's last part, the ride on the dragon's back: the room disappears. The
///   game's space hands over to it (a space cannot switch from mixed to full while open: its content would
///   stop being drawn).
/// Closing the space (Digital Crown) brings the launch window back.
@main
struct MacrowaversApp: App {
    @State private var appModel = AppModel()
    /// "Untangle the Dragon" feature (AR126-100): one view model shared by the windows and the immersive space.
    @State private var untangleViewModel = UntangleViewModel()
    /// The tree's fruit, the ingredients they hide and the elixir that soothes the dragon.
    @State private var orchardViewModel = OrchardViewModel()
    /// The storytelling screens around the game (Start, the narrator, the dragon's words).
    @State private var storyViewModel = StoryViewModel()
    /// The player's settings (Settings window), kept between launches.
    @State private var settings = GameSettings()

    init() {
        DragonBodySystem.registerAll()
        OrchardSystem.registerAll()
        DragonRideSystem.registerAll()
    }

    var body: some Scene {
        WindowGroup(id: ContentView.windowID) {
            ContentView()
                .environment(appModel)
                .environment(untangleViewModel)
                .environment(orchardViewModel)
                .environment(storyViewModel)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)

        Window("Settings", id: SettingsView.windowID) {
            SettingsView()
                .environment(settings)
        }
        .windowResizability(.contentSize)
        // Opened only by the Settings button: never at launch, never brought back on its own.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        ImmersiveSpace(id: DragonImmersiveView.spaceID) {
            DragonImmersiveView()
                .environment(untangleViewModel)
                .environment(orchardViewModel)
                .environment(storyViewModel)
                .environment(settings)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

        ImmersiveSpace(id: DragonRideView.spaceID) {
            DragonRideView()
                .environment(untangleViewModel)
                .environment(orchardViewModel)
                .environment(storyViewModel)
                .environment(settings)
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}
