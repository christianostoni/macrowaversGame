#if os(visionOS)
import RealityKit
import SwiftUI

/// Gestures of the tree's fruit and the elixir's ingredients in the immersive space, and the link between the
/// elixir and the dragon. Every gesture targets its own component, so none of them steals the pinch from the dragon (tap and
/// grabs) or from the island (spin).
struct OrchardInteractions: ViewModifier {
    @Environment(OrchardViewModel.self) private var orchard
    @Environment(UntangleViewModel.self) private var untangle
    /// Gesture state: where the stem drag started, the pinch scale, the grab offset of a seed.
    @State private var stemDragStart: StemDrag?
    @State private var pinchStart: Float?
    @State private var seedGrabOffset: SIMD3<Float>?
    @State private var orbGrab: OrbGrab?

    private struct StemDrag {
        let height: Float
        let opening: Float
    }

    /// An ingredient in the hand: its offset from the pinch, and the hand's and its own rotation when it was taken.
    private struct OrbGrab {
        let offset: SIMD3<Float>
        let handRotation: simd_quatf?
        let orientation: simd_quatf
    }

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(pickFruitGesture)
            .simultaneousGesture(pullStemGesture)
            .simultaneousGesture(catchWormGesture)
            .simultaneousGesture(openPomegranateGesture)
            .simultaneousGesture(dragSeedGesture)
            .simultaneousGesture(openOrangeGesture)
            .simultaneousGesture(chopPineappleGesture)
            .simultaneousGesture(tapOrbGesture)
            .simultaneousGesture(dragOrbGesture)
            // The elixir flies to the dragon (and the ingredients take the pinch) only while it circles the tree.
            .onChange(of: untangle.phase.isOnIsland, initial: true) { _, isOnIsland in
                orchard.isDragonOnIsland = isOnIsland
            }
            // The elixir reached the dragon: soothed, it comes to the player.
            .onChange(of: orchard.elixir.state) { _, state in
                if state == .delivered { untangle.callDragon() }
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

    /// Two hands moving apart split the orange in two, then fan each half into wedges (in the simulator: hold Option).
    private var openOrangeGesture: some Gesture {
        MagnifyGesture()
            .targetedToEntity(where: .has(OrangeBodyComponent.self))
            .onChanged { value in
                let start = pinchStart ?? orchard.orangeOpening
                pinchStart = start
                orchard.setOrangeOpening(start + (Float(value.magnification) - 1) / 0.6)
            }
            .onEnded { _ in
                pinchStart = nil
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

    /// Tap an ingredient: risen out of its fruit it joins the orbit at once (it would a moment later anyway); in
    /// orbit with all the others it brews the elixir, like the snap (always available, also without hand tracking).
    private var tapOrbGesture: some Gesture {
        SpatialTapGesture()
            .targetedToEntity(where: .has(OrbComponent.self))
            .onEnded { value in
                guard let id = value.entity.components[OrbComponent.self]?.fruitID,
                      orchard.orbs.indices.contains(id) else { return }
                switch orchard.orbs[id] {
                case .revealed: orchard.collectOrb(fruit: id)
                case .orbiting: orchard.brewElixir()
                case .sealed, .spent: break
                }
            }
    }
}

extension OrchardInteractions {
    /// Pinch an ingredient in orbit and move it: it follows the hand and turns with the wrist. Let go, it flies back
    /// to its slot around the flask. A pinch that does not move stays a tap (`tapOrbGesture`).
    private var dragOrbGesture: some Gesture {
        DragGesture()
            .targetedToEntity(where: .has(OrbComponent.self))
            .onChanged { value in
                let orb = value.entity
                guard var journey = orb.components[OrbComponent.self], let parent = orb.parent,
                      orchard.orbs.indices.contains(journey.fruitID), case .orbiting = orchard.orbs[journey.fruitID],
                      orchard.elixir.letsIngredientsBeHeld else { return }
                let hand = value.convert(value.location3D, from: .local, to: parent)
                let wrist = value.inputDevicePose3D.map { value.convert($0.rotation, from: .local, to: parent) }
                let grab = orbGrab ?? OrbGrab(offset: orb.position - hand, handRotation: wrist,
                                              orientation: orb.orientation)
                orbGrab = grab
                if !journey.isHeld {
                    journey.isHeld = true
                    orb.components.set(journey)
                }
                orb.position = hand + grab.offset
                if let wrist, let start = grab.handRotation {
                    orb.orientation = wrist * start.inverse * grab.orientation
                }
            }
            .onEnded { value in
                orbGrab = nil
                guard var journey = value.entity.components[OrbComponent.self], journey.isHeld else { return }
                journey.isHeld = false
                journey.joinStart = nil
                journey.joinElapsed = 0
                value.entity.components.set(journey)
            }
    }
}

extension View {
    func orchardInteractions() -> some View {
        modifier(OrchardInteractions())
    }
}
#endif
