#if os(visionOS)
import RealityKit
import SwiftUI

/// Gestures of the tree's fruit and the kalash in the immersive space, and the link between the spell and the
/// dragon. Every gesture targets its own component, so none of them steals the pinch from the dragon (tap and
/// grabs) or from the island (spin).
struct OrchardInteractions: ViewModifier {
    @Environment(OrchardViewModel.self) private var orchard
    @Environment(UntangleViewModel.self) private var untangle
    /// Gesture state: where the stem drag started, the pinch scale, the grab offsets of a seed, an orb, the kalash.
    @State private var stemDragStart: StemDrag?
    @State private var pinchStart: Float?
    @State private var seedGrabOffset: SIMD3<Float>?
    @State private var orbGrabOffset: SIMD3<Float>?
    @State private var kalashGrabOffset: SIMD3<Float>?

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
            .simultaneousGesture(peelBananaGesture)
            .simultaneousGesture(chopPineappleGesture)
            .simultaneousGesture(dragOrbGesture)
            .simultaneousGesture(dragKalashGesture)
            .simultaneousGesture(castSpellGesture)
            // The spell flies to the dragon (and the kalash takes the pinch) only while it circles the tree.
            .onChange(of: untangle.phase.isOnIsland, initial: true) { _, isOnIsland in
                orchard.isDragonOnIsland = isOnIsland
            }
            // The blue spell reached the dragon: soothed, it comes to the player.
            .onChange(of: orchard.kalash.spell) { _, spell in
                if spell == .delivered { untangle.callDragon() }
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

    /// Pinch a strip of the banana's peel and pull it outwards and down: the strip follows the hand.
    private var peelBananaGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .targetedToEntity(where: .has(BananaPeelComponent.self))
            .onChanged { value in
                guard let strip = value.entity.components[BananaPeelComponent.self]?.strip else { return }
                let hand = value.convert(value.location3D, from: .local, to: .scene)
                guard let progress = BananaRig.peelProgress(of: value.entity, handPosition: hand) else { return }
                orchard.setBananaPeel(strip: strip, progress: progress)
            }
    }

    /// Tap the pineapple: it splits open (the hand's chop is read by the `OrchardSystem`).
    private var chopPineappleGesture: some Gesture {
        SpatialTapGesture()
            .targetedToEntity(where: .has(PineappleBodyComponent.self))
            .onEnded { _ in
                orchard.chopPineapple()
            }
    }

    /// Pinch the orb risen out of a fruit and carry it to the kalash: let go over its mouth and it drops in,
    /// anywhere else it floats back above its fruit.
    private var dragOrbGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .targetedToEntity(where: .has(OrbComponent.self))
            .onChanged { value in
                let orb = value.entity
                guard let id = orb.components[OrbComponent.self]?.fruitID, let root = orb.orchardRoot,
                      orchard.grabOrb(fruit: id) else { return }
                // Out of the fruit, into the orchard's space (the scene's): it goes wherever the hand goes.
                if orb.parent !== root { orb.setParent(root, preservingWorldTransform: true) }
                let point = value.convert(value.location3D, from: .local, to: root)
                let offset = orbGrabOffset ?? orb.position - point
                orbGrabOffset = offset
                orb.position = point + offset
            }
            .onEnded { value in
                orbGrabOffset = nil
                let orb = value.entity
                guard let id = orb.components[OrbComponent.self]?.fruitID,
                      let kalash = orb.orchardRoot?.components[OrchardComponent.self]?.kalash else { return }
                let distance = simd_distance(orb.position(relativeTo: nil), kalash.mouth.position(relativeTo: nil))
                orchard.releaseOrb(fruit: id, intoKalash: distance < OrchardComponent.kalashDropRadius)
            }
    }

    /// Drag the kalash wherever is handy: it stays where it is dropped.
    private var dragKalashGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .targetedToEntity(where: .has(KalashComponent.self))
            .onChanged { value in
                guard orchard.isDragonOnIsland, let parent = value.entity.parent else { return }
                let point = value.convert(value.location3D, from: .local, to: parent)
                let offset = kalashGrabOffset ?? value.entity.position - point
                kalashGrabOffset = offset
                value.entity.position = point + offset
            }
            .onEnded { _ in
                kalashGrabOffset = nil
            }
    }

    /// Tap the full kalash: the spell is cast, like the twist (always available, also without hand tracking).
    private var castSpellGesture: some Gesture {
        SpatialTapGesture()
            .targetedToEntity(where: .has(KalashComponent.self))
            .onEnded { _ in
                orchard.castSpell()
            }
    }
}

extension View {
    func orchardInteractions() -> some View {
        modifier(OrchardInteractions())
    }
}
#endif
