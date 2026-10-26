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
    /// Two hands on an ingredient: its size and its rotation when they took it.
    @State private var orbScaleStart: Float?
    @State private var orbTurnStart: simd_quatf?

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
            .simultaneousGesture(peelBananaGesture)
            .simultaneousGesture(openOrangeGesture)
            .simultaneousGesture(chopPineappleGesture)
            .simultaneousGesture(tapOrbGesture)
            .simultaneousGesture(dragOrbGesture)
            .simultaneousGesture(scaleOrbGesture)
            .simultaneousGesture(turnOrbGesture)
            // The elixir flies to the dragon (and the ingredients take the pinch) only while it circles the tree.
            .onChange(of: untangle.phase.isOnIsland, initial: true) { _, isOnIsland in
                orchard.isDragonOnIsland = isOnIsland
            }
            // The elixir flies to the dragon: it stops on its path and lifts its head to receive it. Once the elixir
            // is poured over it, soothed, it comes to the player (not before: the flask would chase it).
            .onChange(of: orchard.elixirState) { _, state in
                switch state {
                case .flying: untangle.receiveElixir()
                case .poured: untangle.callDragon()
                default: break
                }
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
                let lift = orchard.appleShape.maxLift * OrchardSceneBuilder.appleSizeFocused / orchard.appleShape.width
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
                guard hold(orb), let parent = orb.parent else { return }
                let hand = value.convert(value.location3D, from: .local, to: parent)
                let wrist = value.inputDevicePose3D.map { value.convert($0.rotation, from: .local, to: parent) }
                let grab = orbGrab ?? OrbGrab(offset: orb.position - hand, handRotation: wrist,
                                              orientation: orb.orientation)
                orb.position = hand + grab.offset
                if orbTurnStart != nil {
                    // Two hands turn it: the wrist takes over from where they leave it.
                    orbGrab = OrbGrab(offset: grab.offset, handRotation: wrist, orientation: orb.orientation)
                } else {
                    orbGrab = grab
                    if let wrist, let start = grab.handRotation {
                        orb.orientation = wrist * start.inverse * grab.orientation
                    }
                }
            }
            .onEnded { value in
                orbGrab = nil
                releaseIfFree(value.entity)
            }
    }

    /// Two hands moving apart or together make an ingredient in orbit bigger or smaller (in the simulator: hold
    /// Option). Let go, it takes back its own size on the way to its slot.
    private var scaleOrbGesture: some Gesture {
        MagnifyGesture()
            .targetedToEntity(where: .has(OrbComponent.self))
            .onChanged { value in
                let orb = value.entity
                guard hold(orb), var journey = orb.components[OrbComponent.self] else { return }
                let start = orbScaleStart ?? journey.heldScale
                orbScaleStart = start
                let range = OrbComponent.heldScaleRange
                let scale = min(max(start * Float(value.magnification), range.lowerBound), range.upperBound)
                guard journey.heldScale != scale else { return }
                journey.heldScale = scale
                orb.components.set(journey)
            }
            .onEnded { value in
                orbScaleStart = nil
                releaseIfFree(value.entity)
            }
    }

    /// Two hands turning around an ingredient in orbit turn it, about any axis (in the simulator: hold Option). Let
    /// go, it turns upright again on the way to its slot.
    private var turnOrbGesture: some Gesture {
        RotateGesture3D()
            .targetedToEntity(where: .has(OrbComponent.self))
            .onChanged { value in
                let orb = value.entity
                guard hold(orb), let parent = orb.parent else { return }
                let start = orbTurnStart ?? orb.orientation
                orbTurnStart = start
                // SwiftUI space has y pointing down: the axis keeps its y and flips its x and z in RealityKit space.
                let turn = value.rotation.quaternion
                let sceneTurn = simd_quatf(ix: Float(-turn.imag.x), iy: Float(turn.imag.y), iz: Float(-turn.imag.z),
                                           r: Float(turn.real))
                let frame = parent.orientation(relativeTo: nil)
                orb.orientation = frame.inverse * sceneTurn * frame * start
            }
            .onEnded { value in
                orbTurnStart = nil
                releaseIfFree(value.entity)
            }
    }

    /// Takes an ingredient out of its orbit while a gesture holds it; false when it cannot be held (not in orbit,
    /// or the elixir is brewing).
    private func hold(_ orb: Entity) -> Bool {
        guard var journey = orb.components[OrbComponent.self], orchard.orbs.indices.contains(journey.fruitID),
              case .orbiting = orchard.orbs[journey.fruitID], orchard.elixir.letsIngredientsBeHeld else { return false }
        if !journey.isHeld {
            journey.isHeld = true
            orb.components.set(journey)
        }
        return true
    }

    /// The last gesture on an ingredient ended: it flies back to its slot like it came from its fruit.
    private func releaseIfFree(_ orb: Entity) {
        guard orbGrab == nil, orbScaleStart == nil, orbTurnStart == nil,
              var journey = orb.components[OrbComponent.self], journey.isHeld else { return }
        journey.isHeld = false
        journey.joinStart = nil
        journey.joinElapsed = 0
        orb.components.set(journey)
    }
}

extension View {
    func orchardInteractions() -> some View {
        modifier(OrchardInteractions())
    }
}
#endif
