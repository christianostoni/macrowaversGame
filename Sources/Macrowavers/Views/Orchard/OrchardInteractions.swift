#if os(visionOS)
import RealityKit
import SwiftUI

/// Gestures of the tree's fruit in the immersive space, and the link between the fruit and the dragon.
/// Every gesture targets its own component, so none of them steals the pinch from the dragon (tap and grabs)
/// or from the island (spin).
struct OrchardInteractions: ViewModifier {
    @Environment(OrchardViewModel.self) private var orchard
    @Environment(UntangleViewModel.self) private var untangle
    /// Gesture state: where the stem drag started, the pinch scale, the grab offset of a seed.
    @State private var stemDragStart: StemDrag?
    @State private var pinchStart: Float?
    @State private var seedGrabOffset: SIMD3<Float>?

    private struct StemDrag {
        let height: Float
        let opening: Float
    }

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(pickFruitGesture)
            .simultaneousGesture(pullStemGesture)
            .simultaneousGesture(catchWormGesture)
            .simultaneousGesture(openPomegranateGesture)
            .simultaneousGesture(dragSeedGesture)
            .simultaneousGesture(useArtifactGesture)
            // The artifact reached the dragon: soothed, it comes to the player.
            .onChange(of: orchard.artifact) { _, artifact in
                if artifact == .used { untangle.callDragon() }
            }
    }

    /// Tap a fruit on the tree: it comes close. Only while the dragon is still on the island.
    private var pickFruitGesture: some Gesture {
        SpatialTapGesture()
            .targetedToEntity(where: .has(FruitTapTargetComponent.self))
            .onEnded { value in
                guard untangle.phase.isOnIsland, let fruit = value.entity.components[FruitComponent.self] else { return }
                orchard.focus(fruit: fruit.id)
            }
    }

    /// Pull the apple's stem up: the slices open.
    private var pullStemGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .targetedToEntity(where: .has(AppleStemComponent.self))
            .onChanged { value in
                let height = value.convert(value.location3D, from: .local, to: .scene).y
                let start = stemDragStart ?? StemDrag(height: height, opening: orchard.appleOpening)
                stemDragStart = start
                // Fully open = the stem raised by `maxLift` at the apple's size in front of the player.
                let lift = orchard.appleShape.maxLift * OrchardSceneBuilder.appleSizeFocused / orchard.appleShape.height
                orchard.setAppleOpening(start.opening + (height - start.height) / lift)
            }
            .onEnded { _ in
                stemDragStart = nil
            }
    }

    private var catchWormGesture: some Gesture {
        SpatialTapGesture()
            .targetedToEntity(where: .has(WormComponent.self))
            .onEnded { value in
                guard let worm = value.entity.components[WormComponent.self] else { return }
                orchard.catchWorm(worm.index)
            }
    }

    /// Two hands moving apart open the pomegranate (in the simulator: hold Option).
    private var openPomegranateGesture: some Gesture {
        MagnifyGesture()
            .targetedToEntity(where: .has(PomegranateBodyComponent.self))
            .onChanged { value in
                let start = pinchStart ?? orchard.pomegranateOpening
                pinchStart = start
                orchard.setPomegranateOpening(start + (Float(value.magnification) - 1) / 0.6)
            }
            .onEnded { _ in
                pinchStart = nil
            }
    }

    /// Drag a pomegranate seed that has burst out (pure play: no game state).
    private var dragSeedGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .targetedToEntity(where: .has(SeedComponent.self))
            .onChanged { value in
                guard let parent = value.entity.parent, value.entity.components.has(FloatingComponent.self) else { return }
                let point = value.convert(value.location3D, from: .local, to: parent)
                let offset = seedGrabOffset ?? PomegranateRig.home(of: value.entity) - point
                seedGrabOffset = offset
                PomegranateRig.moveSeed(value.entity, to: point + offset)
            }
            .onEnded { value in
                PomegranateRig.endSeedDrag(value.entity)
                seedGrabOffset = nil
            }
    }

    /// Tap the artifact freed from the apple: it flies to the dragon.
    private var useArtifactGesture: some Gesture {
        SpatialTapGesture()
            .targetedToEntity(where: .has(ArtifactComponent.self))
            .onEnded { _ in
                guard untangle.phase.isOnIsland else { return }
                orchard.useArtifact()
            }
    }
}

extension View {
    func orchardInteractions() -> some View {
        modifier(OrchardInteractions())
    }
}
#endif
