import SwiftUI

/// Gerarchia delle scene:
/// - finestra principale (isola): avvio, gestione dell'ambiente, riavvio di tutto il gioco;
/// - pannello del drago: `Window` a istanza unica, aperto solo toccando il drago, mai ripristinato all'avvio;
/// - spazio immersivo (.mixed) con l'isola e il drago.
/// Tutte condividono un solo ViewModel; aprono e chiudono le altre solo la finestra principale e lo spazio.
@main
struct MacrowaversApp: App {
    @State private var appModel = AppModel()
    /// Feature "Untangle the Dragon" (AR126-100): un solo ViewModel condiviso da finestre e spazio immersivo.
    @State private var untangleViewModel = UntangleViewModel()

    init() {
        DragonBodySystem.registerAll()
    }

    var body: some Scene {
        WindowGroup(id: ContentView.windowID) {
            ContentView()
                .environment(appModel)
                .environment(untangleViewModel)
        }
        .windowResizability(.contentSize)

        Window("Dragon", id: DragonPanelView.windowID) {
            DragonPanelView()
                .environment(untangleViewModel)
        }
        .windowResizability(.contentSize)
        // Si apre solo dal gioco: non all'avvio dell'app e non ripristinato da una sessione precedente.
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
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
