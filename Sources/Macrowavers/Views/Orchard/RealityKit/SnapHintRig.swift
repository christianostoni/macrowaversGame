import RealityKit
import simd
import UIKit

/// The hologram hand drawn in RealityKit (`SnapHint` decides its pose, this only draws): a ghostly white hand, one
/// smooth see-through skin (`HandSurface`), to the left of the flask, facing the player, snapping its fingers in a
/// loop, with a puff of sparks at each snap.
///
/// The loop is fixed, so its skin is too: one mesh per frame at `SnapHintBake.framesPerSecond` (a frame that holds
/// the previous pose reuses its mesh), swapped into one model as the loop plays. The meshes are baked ahead of time
/// (`SnapHintBake`, the `SnapHintHand.bin` resource) and read from the orchard's first frame (`prepareIfNeeded()`):
/// ~0.15 s on a background thread, even in a Debug build, so the hand is ready long before the orbit is complete.
/// Built at run time they took ~20 s of processor time in a Debug build and showed up late; that stays only as the
/// fallback when the resource does not match the code (bake it again): one mesh at a time, on a single background
/// thread, so the frames are never starved.
/// The model has a sort group with a depth pre-pass: only the hand's outer surface is drawn, so the fingers in front
/// of the palm do not show it through them. The fade, the flicker and the flash of the snap go through one
/// `OpacityComponent` on the root.
@MainActor
final class SnapHintRig {
    static let name = "SnapHint"
    /// The hand's size (1 = an adult's hand, ~19 cm from the wrist to the middle fingertip) and its height in hand
    /// space at its tallest (the open hand).
    static let scale: Float = 0.8
    static let handHeight: Float = 0.19
    /// The hand's middle this far to the left of the orbit's centre (m, along the orbit's side-to-side axis) and this
    /// far below it: next to the flask, a little lower, clear of the ingredients' path all the way round (from the
    /// eyes, 3° from it at the closest, 5 cm in space; 9° from the flask). Seen from the eyes the hand spans ~3–12°
    /// to the right and ~13–26° below the horizon (the flask: 30° right, 17° down): it shows only while no fruit is
    /// close, so it never covers one.
    static let side: Float = 0.25
    static let drop: Float = 0.06
    /// The hand turned from facing the player (radians, around the vertical): its palm turns to the left, the thumb
    /// comes towards the player, so they see the thumb on the middle finger and the finger flick into the palm.
    static let turn: Float = -50 * .pi / 180
    /// Leaning back (radians): the player looks down at it, its palm faces their eyes.
    static let lean: Float = 0.3
    /// Opacity of the hand at rest, the extra at the snap's flash and while the player's own hand is ready to snap.
    static let opacity: Float = 0.6
    static let flashOpacity: Float = 0.3
    static let readyOpacity: Float = 0.15

    /// Placed and turned by `OrchardSystem.updateSnapHint`, in the orchard's root.
    let root = Entity()
    /// The hand's own space (`SnapHint`): turned and scaled under `root`.
    private let hand: ModelEntity
    private let sparks: Entity
    /// One mesh per distinct pose, and which one each frame of the loop shows (empty until prepared).
    private var meshes: [MeshResource] = []
    private var frames: [Int] = []
    private var shownMesh: Int?
    private var isPreparing = false

    init() {
        root.name = Self.name
        root.isEnabled = false
        hand = ModelEntity()
        hand.orientation = simd_quatf(angle: Self.turn, axis: SIMD3(0, 1, 0))
        hand.scale = SIMD3(repeating: Self.scale)
        hand.components.set(ModelSortGroupComponent(group: ModelSortGroup(depthPass: .prePass), order: 0))
        root.addChild(hand)

        sparks = Self.makeSparks()
        sparks.position = SnapHint.pose(at: SnapHint.snapTime - 0.1).middlePad
        hand.addChild(sparks)
    }

    /// Starts building the loop's meshes, once.
    func prepareIfNeeded() {
        guard !isPreparing else { return }
        isPreparing = true
        Task { await prepare() }
    }

    /// Reads the loop's baked meshes (~7k vertices each) off the main thread, or, if they do not match the code,
    /// builds them one after the other at background priority (one core, never all of them); hands them to
    /// RealityKit one at a time. The hand shows once they are all ready.
    private func prepare() async {
        let baked = await Task.detached(priority: .utility) { Self.bakedSkins() }.value
        let loop = baked == nil ? SnapHintBake.loop() : (poses: [], frames: [])
        let frames = baked?.frames ?? loop.frames
        var meshes: [MeshResource] = []
        for index in 0..<(baked?.skins.count ?? loop.poses.count) {
            let skin: HandSurface.Mesh
            if let baked {
                skin = baked.skins[index].mesh
            } else {
                let pose = loop.poses[index]
                skin = await Task.detached(priority: .background) { HandSurface(pose: pose).mesh() }.value
            }
            guard let mesh = try? await MeshResource(from: [Self.descriptor(skin)]) else {
                print("⚠️ The hologram hand's mesh could not be built: no hand")
                return
            }
            meshes.append(mesh)
        }
        hand.model = ModelComponent(mesh: meshes[0], materials: [Self.material()])
        self.meshes = meshes
        self.frames = frames
    }

    /// Draws the hand of `hint`, its wrist at `wrist`, facing `eyes` (both in the root's parent space).
    func draw(_ hint: SnapHint, wrist: SIMD3<Float>, facing eyes: SIMD3<Float>, isPlayerReady: Bool, time: Float) {
        root.isEnabled = hint.presence > 0 && !meshes.isEmpty
        guard root.isEnabled else { return }
        let toEyes = eyes - wrist
        root.position = wrist + SIMD3(0, 0.005 * sin(time * 1.6), 0)
        root.orientation = simd_quatf(angle: atan2(toEyes.x, toEyes.z), axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: -Self.lean, axis: SIMD3(1, 0, 0))
        // A hologram's shimmer: a faint, uneven flicker.
        let flicker = 0.04 * sin(time * 23) * sin(time * 7.3)
        let opacity = hint.presence * (Self.opacity + flicker + Self.flashOpacity * hint.flash
            + (isPlayerReady ? Self.readyOpacity : 0))
        root.components.set(OpacityComponent(opacity: min(max(opacity, 0), 1)))

        let frame = min(max(Int(hint.time * SnapHintBake.framesPerSecond), 0), frames.count - 1)
        let mesh = frames[frame]
        if mesh != shownMesh {
            hand.model?.mesh = meshes[mesh]
            shownMesh = mesh
        }
        if hint.didSnap { ElixirRig.burst(sparks) }
    }

    /// The baked skins, if the resource is there and matches the code.
    private nonisolated static func bakedSkins() -> SnapHintBake? {
        guard let url = Bundle.main.url(forResource: SnapHintBake.resourceName,
                                        withExtension: SnapHintBake.resourceExtension),
              let bake = try? SnapHintBake(data: Data(contentsOf: url)) else {
            print("⚠️ The hologram hand's baked meshes are missing: building them (slow in a Debug build)")
            return nil
        }
        guard bake.matchesCode else {
            print("⚠️ The hologram hand's baked meshes are out of date: building them (slow in a Debug build); "
                + "run sh Assets/SnapHint/make_snap_hint_hand.sh")
            return nil
        }
        return bake
    }

    private static func descriptor(_ skin: HandSurface.Mesh) -> MeshDescriptor {
        var descriptor = MeshDescriptor(name: "SnapHintHand")
        descriptor.positions = MeshBuffers.Positions(skin.positions)
        descriptor.normals = MeshBuffers.Normals(skin.normals)
        descriptor.primitives = .triangles(skin.indices)
        return descriptor
    }

    /// Pale, softly glowing, see-through: lit enough to show the hand's shape.
    private static func material() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.9, green: 0.96, blue: 1, alpha: 1))
        material.roughness = 0.4
        material.metallic = 0.0
        material.emissiveColor = .init(color: UIColor(red: 0.82, green: 0.92, blue: 1, alpha: 1))
        material.emissiveIntensity = 0.9
        material.blending = .transparent(opacity: .init(floatLiteral: 0.8))
        // Both sides: the depth pre-pass already hides the far side.
        material.faceCulling = .none
        return material
    }

    /// A small puff of white sparks where the thumb leaves the middle finger.
    private static func makeSparks() -> Entity {
        let entity = Entity()
        var sparks = ParticleEmitterComponent()
        sparks.emitterShape = .sphere
        sparks.emitterShapeSize = SIMD3(repeating: 0.01)
        sparks.birthDirection = .normal
        sparks.speed = 0.18
        sparks.speedVariation = 0.08
        sparks.isEmitting = false
        sparks.burstCount = 50
        sparks.mainEmitter.lifeSpan = 0.45
        sparks.mainEmitter.size = 0.0025
        sparks.mainEmitter.color = .evolving(start: .single(.white),
                                             end: .single(UIColor(red: 0.7, green: 0.88, blue: 1, alpha: 1)))
        entity.components.set(sparks)
        return entity
    }
}

// MARK: - System

extension OrchardSystem {
    /// The hologram hand: shown with every ingredient in orbit (until the snap), while no fruit is in front of the
    /// player, to the left of the flask. Brighter while the player's own hand holds the loaded pose. Its baked
    /// meshes are read on the orchard's first frame (the world is loaded by then), in the background.
    @MainActor
    static func updateSnapHint(_ orchard: inout OrchardComponent, deltaTime: Float) {
        let viewModel = orchard.viewModel
        orchard.snapRig.prepareIfNeeded()
        let isShown = viewModel.elixir.state == .ready && viewModel.focusedFruitID == nil
        orchard.snapHint.update(deltaTime: deltaTime, isShown: isShown)
        let middle = orchard.orbit.center - orchard.orbit.across * SnapHintRig.side - SIMD3(0, SnapHintRig.drop, 0)
        let height = SnapHintRig.handHeight * SnapHintRig.scale * cos(SnapHintRig.lean)
        orchard.snapRig.draw(orchard.snapHint, wrist: middle - SIMD3(0, height / 2, 0),
                             facing: orchard.viewer.viewerPose().position, isPlayerReady: orchard.snap.isLoaded,
                             time: orchard.time)
    }
}
