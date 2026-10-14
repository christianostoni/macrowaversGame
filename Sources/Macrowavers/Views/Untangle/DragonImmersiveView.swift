#if os(visionOS)
import RealityKit
import SwiftUI

/// Spazio immersivo in mixed reality: un'isola volante (che l'utente fa girare) con il drago prigioniero
/// attorno all'albero. Toccato, il drago si arrabbia e si apre il suo pannello; chiamato, vola dall'utente
/// e si posa aggrovigliato davanti a lui; sgrovigliato, vola via nel cielo.
struct DragonImmersiveView: View {
    static let spaceID = "DragonSpace"

    /// Giradischi: di quanto gira l'isola rispetto all'angolo descritto dalla mano attorno al tronco.
    private static let spinGain: Float = 2

    @Environment(UntangleViewModel.self) private var viewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    /// Rotazione dell'isola all'inizio del gesto in corso.
    @State private var islandYawStart: Float?
    /// Iscrizioni agli eventi di presa sul drago: vanno tenute vive finché la view esiste.
    @State private var subscriptions: [EventSubscription] = []
    /// Posizione della testa dell'utente: il drago guarda il cavaliere.
    @State private var viewer = ViewerTracker()

    var body: some View {
        RealityView { content in
            // Prima l'isola: il drago nasce già attorno al suo albero.
            let island = await IslandSceneBuilder.makeIsland(placement: viewModel.islandPlacement)
            content.add(island.root)
            content.add(await DragonSceneBuilder.makePlayArea(viewModel: viewModel, viewer: viewer,
                                                              orbitAnchor: island.treeAnchor))
            subscriptions = subscribeToDragonGrabs(content)
        } update: { content in
            // Leggere `placement`/`islandPlacement` qui fa ri-eseguire questo blocco a ogni cambio.
            if let island = content.entities.first(where: { $0.name == IslandSceneBuilder.islandName }),
               var turntable = island.components[TurntableComponent.self] {
                turntable.targetYaw = viewModel.islandPlacement.yaw
                island.components.set(turntable)
            }
            let placement = viewModel.placement
            guard let playArea = content.entities.first(where: { $0.name == DragonSceneBuilder.playAreaName }) else { return }
            playArea.position = placement.position
            playArea.orientation = placement.rotation
        }
        .gesture(tapDragonGesture)
        .simultaneousGesture(spinIslandGesture)
        .simultaneousGesture(rotateIslandGesture)
        .task { await viewer.start() }
        .onAppear { viewModel.immersiveSpaceState = .open }
        .onDisappear {
            // Chiuso dal pannello o dal sistema (Digital Crown): niente finestre orfane, si riparte da capo.
            viewer.stop()
            dismissWindow(id: DragonPanelView.windowID)
            viewModel.resetGame()
            viewModel.immersiveSpaceState = .closed
        }
    }

    // MARK: - Drago

    /// Guarda il drago che gira attorno all'albero e pizzica: si arrabbia e si apre il suo pannello.
    /// Solo i collider con `DragonTapTargetComponent` rispondono (cioè solo mentre è sull'isola).
    private var tapDragonGesture: some Gesture {
        SpatialTapGesture()
            .targetedToEntity(where: .has(DragonTapTargetComponent.self))
            .onEnded { _ in
                viewModel.tapDragon()
                // `Window` a istanza unica: se è già aperto torna in primo piano, non si duplica.
                openWindow(id: DragonPanelView.windowID)
            }
    }

    // MARK: - Isola

    /// Trascina la roccia dell'isola: gira come un giradischi attorno al tronco.
    private var spinIslandGesture: some Gesture {
        DragGesture()
            .targetedToEntity(where: .has(IslandHandleComponent.self))
            .onChanged { value in
                let start = islandYawStart ?? viewModel.islandPlacement.yaw
                islandYawStart = start
                let center = viewModel.islandPlacement.position
                let from = value.convert(value.startLocation3D, from: .local, to: .scene)
                let to = value.convert(value.location3D, from: .local, to: .scene)
                // Angolo descritto dalla mano attorno al tronco (stesso verso della rotazione attorno a +Y).
                let turn = atan2(to.x - center.x, to.z - center.z) - atan2(from.x - center.x, from.z - center.z)
                viewModel.setIslandYaw(start + Self.spinGain * atan2(sin(turn), cos(turn)))
            }
            .onEnded { _ in
                islandYawStart = nil
            }
    }

    /// Ruota l'isola con due mani (nel simulatore: tieni premuto Option).
    private var rotateIslandGesture: some Gesture {
        RotateGesture3D(constrainedToAxis: .y)
            .targetedToEntity(where: .has(IslandHandleComponent.self))
            .onChanged { value in
                let start = islandYawStart ?? viewModel.islandPlacement.yaw
                islandYawStart = start
                let quaternion = value.rotation.quaternion
                let angle = Float(2 * atan2(quaternion.imag.y, quaternion.real))
                // Lo spazio SwiftUI ha la y verso il basso: segno invertito rispetto a RealityKit.
                viewModel.setIslandYaw(start - angle)
            }
            .onEnded { _ in
                islandYawStart = nil
            }
    }

    /// Ogni nodo del drago ha un `ManipulationComponent`: ogni mano afferra e muove il proprio nodo,
    /// quindi si possono tenere due parti del corpo contemporaneamente.
    /// Qui si avvisa il ViewModel di inizio/fine presa; il movimento lo legge il `DragonBodySystem`.
    private func subscribeToDragonGrabs(_ content: RealityViewContent) -> [EventSubscription] {
        [
            content.subscribe(to: ManipulationEvents.WillBegin.self) { event in
                guard let node = event.entity.components[DragonNodeComponent.self] else { return }
                viewModel.grab(node: node.index)
            },
            content.subscribe(to: ManipulationEvents.WillRelease.self) { event in
                guard let node = event.entity.components[DragonNodeComponent.self] else { return }
                viewModel.release(node: node.index)
            },
            // Sicurezza: se la presa termina senza rilascio (es. annullata), il nodo va comunque liberato.
            content.subscribe(to: ManipulationEvents.WillEnd.self) { event in
                guard let node = event.entity.components[DragonNodeComponent.self] else { return }
                viewModel.release(node: node.index)
            },
        ]
    }
}

#Preview(immersionStyle: .mixed) {
    DragonImmersiveView()
        .environment(UntangleViewModel())
}
#endif
