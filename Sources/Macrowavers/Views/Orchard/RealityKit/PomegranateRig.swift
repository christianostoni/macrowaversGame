import RealityKit
import simd

/// The design team's pomegranate (`Pomegranate.usdz`, made by `Assets/Blender/pomegranate`): two halves that open
/// like a book and, fully open, burst into a cloud of seeds that float and can be dragged around. Opening and burst
/// come from `OrchardViewModel`. Origin at the centre of the fruit; the cut faces turn towards +Z (the player when
/// focused).
@MainActor
final class PomegranateRig {
    static let assetName = "Pomegranate"

    let root = Entity()
    /// Where the orb sits until the seeds burst out (centre of the fruit).
    let orbAnchor = Entity()
    /// Half the fruit's width (m): the asset is at real size.
    let radius: Float

    private let body = Entity()
    /// Moved and turned to open the fruit. The asset's halves hang from them as they are: their own transforms
    /// carry the file's Z-up → Y-up turn, which the opening must not overwrite.
    private let rightPivot = Entity()
    private let leftPivot = Entity()
    private var seeds: [Entity] = []
    private var appliedOpening: Float = -1
    /// Opening currently drawn: eases towards the requested one, so the halves never snap shut.
    private var displayedOpening: Float = 0
    /// Where each seed sits packed inside the fruit (they fly back there when the fruit closes).
    private var packedTransforms: [Transform] = []
    private var hasBurst = false
    /// Increases on every reset: a burst still settling must not touch the new seeds.
    private var burstGeneration = 0

    init?() async {
        guard let asset = try? await Entity(named: Self.assetName, in: .main),
              let rightHalf = asset.findEntity(named: "RightHalf"),
              let leftHalf = asset.findEntity(named: "LeftHalf") else {
            print("⚠️ \(Self.assetName).usdz not found (or without RightHalf/LeftHalf): no pomegranate on the tree")
            return nil
        }
        radius = asset.visualBounds(relativeTo: asset).extents.x / 2

        root.addChild(body)
        body.addChild(rightPivot)
        body.addChild(leftPivot)
        // The asset joins the rig only to hand its parts over, keeping where they are.
        root.addChild(asset)
        rightHalf.setParent(rightPivot, preservingWorldTransform: true)
        leftHalf.setParent(leftPivot, preservingWorldTransform: true)
        seeds = (0..<1000).lazy
            .map { asset.findEntity(named: String(format: "Seed_%02d", $0)) }
            .prefix { $0 != nil }
            .compactMap { $0 }
        for seed in seeds {
            seed.setParent(root, preservingWorldTransform: true)
            seed.components.set(SeedComponent())
            // Larger than the seed: easier to grab.
            seed.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.016)]))
        }
        packedTransforms = seeds.map(\.transform)
        asset.removeFromParent()

        // Target of the two-handed gesture that pulls it apart.
        body.components.set(PomegranateBodyComponent())
        // Covers both halves even fully open (they move up to 12 cm sideways), so pulling them apart or
        // pushing them back together always lands on the fruit.
        body.components.set(CollisionComponent(shapes: [
            .generateBox(width: 2 * (0.12 + radius * 1.1), height: radius * 2.2, depth: radius * 2.4),
        ]))
        body.components.set(InputTargetComponent.disabled)
        root.addChild(orbAnchor)
        apply(opening: 0, burst: false)
    }

    // MARK: - Updates from the view model

    /// Moves the drawn opening towards `target`; the seeds burst out or fly back in with `burst`.
    func ease(towards target: Float, burst: Bool, deltaTime: Float) {
        let rate: Float = target < displayedOpening ? 4 : 14
        displayedOpening += (target - displayedOpening) * (1 - exp(-deltaTime * rate))
        if abs(target - displayedOpening) < 0.002 { displayedOpening = target }
        apply(opening: displayedOpening, burst: burst)
    }

    /// 0 = closed, 1 = open: the halves move apart and turn like a book, showing the cut faces.
    func apply(opening: Float, burst: Bool) {
        if opening != appliedOpening {
            appliedOpening = opening
            let angle = opening * 0.4 * .pi
            let distance = opening * 0.12
            rightPivot.position = SIMD3(distance, 0, 0)
            rightPivot.orientation = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
            // The left half is its own mirror image: it turns the other way.
            leftPivot.position = SIMD3(-distance, 0, 0)
            leftPivot.orientation = simd_quatf(angle: -angle, axis: SIMD3(0, 1, 0))
        }
        if burst && !hasBurst {
            burstSeeds()
        } else if !burst && hasBurst {
            gatherSeeds()
        }
    }

    func setInteractive(_ isInteractive: Bool) {
        body.components[InputTargetComponent.self]?.isEnabled = isInteractive
        for seed in seeds where seed.components.has(FloatingComponent.self) {
            seed.components[InputTargetComponent.self]?.isEnabled = isInteractive
        }
    }

    // MARK: - Seeds (dragged directly by the immersive view: pure play, no game state)

    /// Moves a free seed (position in the seed's parent space).
    static func moveSeed(_ seed: Entity, to position: SIMD3<Float>) {
        guard var floating = seed.components[FloatingComponent.self] else { return }
        floating.base = position
        // Still while in the hand.
        floating.isPaused = true
        seed.components.set(floating)
    }

    static func endSeedDrag(_ seed: Entity) {
        guard var floating = seed.components[FloatingComponent.self] else { return }
        floating.isPaused = false
        seed.components.set(floating)
    }

    /// Rest position of a free seed (to keep the grab offset while dragging).
    static func home(of seed: Entity) -> SIMD3<Float> {
        seed.components[FloatingComponent.self]?.base ?? seed.position
    }

    /// The seeds fly back into the fruit (they do not vanish) and stop being draggable.
    private func gatherSeeds() {
        burstGeneration += 1
        hasBurst = false
        for (index, seed) in seeds.enumerated() where index < packedTransforms.count {
            seed.components.remove(FloatingComponent.self)
            seed.components.remove(InputTargetComponent.self)
            seed.components.remove(HoverEffectComponent.self)
            seed.move(to: packedTransforms[index], relativeTo: root, duration: 0.5 + Double(index % 5) * 0.05,
                      timingFunction: .easeIn)
        }
    }

    private func burstSeeds() {
        hasBurst = true
        burstGeneration += 1
        let generation = burstGeneration
        for (index, seed) in seeds.enumerated() {
            var target = seed.transform
            target.translation = Self.cloudPoint()
            seed.move(to: target, relativeTo: root, duration: 0.8 + Double(index % 5) * 0.08, timingFunction: .easeOut)
        }
        // When the burst settles the seeds start floating and can be grabbed.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.3))
            guard let self, self.burstGeneration == generation else { return }
            for seed in self.seeds {
                seed.components.set(FloatingComponent(base: seed.position, amplitude: 0.004,
                                                      period: .random(in: 4...7.5), phase: .random(in: 0...(2 * .pi))))
                seed.components.set(InputTargetComponent())
                seed.components.set(HoverEffectComponent())
            }
        }
    }

    /// Random point in a cloud in front of the fruit.
    private static func cloudPoint() -> SIMD3<Float> {
        let point = randomInUnitSphere()
        return SIMD3(point.x * 0.14, 0.04 + point.y * 0.08, 0.2 + point.z * 0.06)
    }

    private static func randomInUnitSphere() -> SIMD3<Float> {
        while true {
            let point = SIMD3<Float>(.random(in: -1...1), .random(in: -1...1), .random(in: -1...1))
            if simd_length(point) <= 1 { return point }
        }
    }
}
