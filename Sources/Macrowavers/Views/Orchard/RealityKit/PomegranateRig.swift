import RealityKit
import simd
import UIKit

/// The pomegranate drawn in RealityKit: two halves that open like a book and, fully open, burst into a
/// cloud of seeds that float and can be dragged around. Opening and burst come from `OrchardViewModel`.
/// Origin at the centre of the fruit; the cut faces turn towards +Z (the player when focused).
@MainActor
final class PomegranateRig {
    let root = Entity()
    let radius: Float = 0.08

    private let body = Entity()
    private let rightHalf: ModelEntity
    private let leftHalf: ModelEntity
    private var seeds: [Entity] = []
    private let seedMaterial: PhysicallyBasedMaterial
    private var appliedOpening: Float = -1
    /// Opening currently drawn: eases towards the requested one, so the halves never snap shut.
    private var displayedOpening: Float = 0
    /// Where each seed sits packed inside the fruit (they fly back there when the fruit closes).
    private var packedTransforms: [Transform] = []
    private var hasBurst = false
    /// Increases on every reset: a burst still settling must not touch the new seeds.
    private var burstGeneration = 0

    private static let seedCount = 40

    init?() {
        let skin = Self.material(red: 0.62, green: 0.08, blue: 0.16, roughness: 0.55)
        let inner = Self.material(red: 0.98, green: 0.88, blue: 0.78, roughness: 0.8)
        seedMaterial = Self.material(red: 0.78, green: 0.04, blue: 0.16, roughness: 0.12)

        guard let mesh = try? Self.makeHalfMesh(radius: radius) else { return nil }
        rightHalf = ModelEntity(mesh: mesh, materials: [skin, inner])
        leftHalf = ModelEntity(mesh: mesh, materials: [skin, inner])
        // Mirrored half.
        leftHalf.orientation = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))
        rightHalf.addChild(Self.makeCrown(material: skin, topY: radius * 0.9))

        body.addChild(rightHalf)
        body.addChild(leftHalf)
        // Target of the two-handed gesture that pulls it apart.
        body.components.set(PomegranateBodyComponent())
        body.components.set(CollisionComponent(shapes: [.generateSphere(radius: radius * 1.1)]))
        body.components.set(InputTargetComponent.disabled)
        root.addChild(body)

        spawnSeeds()
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
            rightHalf.position = SIMD3(distance, 0, 0)
            rightHalf.orientation = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
            leftHalf.position = SIMD3(-distance, 0, 0)
            leftHalf.orientation = simd_quatf(angle: .pi - angle, axis: SIMD3(0, 1, 0))
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

    private func spawnSeeds() {
        seeds = []
        packedTransforms = []
        for _ in 0..<Self.seedCount {
            let seed = Entity()
            let model = ModelEntity(mesh: .generateSphere(radius: 0.008), materials: [seedMaterial])
            // Drop shaped.
            model.scale = SIMD3(0.9, 1.3, 0.9)
            seed.addChild(model)

            // Packed inside the fruit.
            let point = Self.randomInUnitSphere()
            seed.position = SIMD3(point.x * 0.055, point.y * 0.05, point.z * 0.055)
            seed.orientation = simd_quatf(angle: .random(in: 0...(2 * .pi)),
                                          axis: simd_normalize(Self.randomInUnitSphere() + SIMD3(0, 0.01, 0)))
            seed.components.set(SeedComponent())
            // Larger than the seed: easier to grab.
            seed.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.016)]))
            root.addChild(seed)
            seeds.append(seed)
            packedTransforms.append(seed.transform)
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

    // MARK: - Geometry

    /// Half sphere (x ≥ 0), slightly squashed, plus the cut face on the plane x = 0.
    private static func makeHalfMesh(radius: Float) throws -> MeshResource {
        let squash: Float = 0.9
        let rings = 24
        let sectors = 24

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for ring in 0...rings {
            let polar = Float.pi * Float(ring) / Float(rings)
            for sector in 0...sectors {
                let azimuth = -Float.pi / 2 + Float.pi * Float(sector) / Float(sectors)
                let unit = SIMD3<Float>(sin(polar) * cos(azimuth), cos(polar), sin(polar) * sin(azimuth))
                positions.append(SIMD3(radius * unit.x, radius * squash * unit.y, radius * unit.z))
                normals.append(simd_normalize(SIMD3(unit.x, unit.y / squash, unit.z)))
            }
        }
        let columns = sectors + 1
        for ring in 0..<rings {
            for sector in 0..<sectors {
                let first = UInt32(ring * columns + sector)
                let below = first + UInt32(columns)
                indices += [first, below, first + 1, first + 1, below, below + 1]
            }
        }
        var skin = MeshDescriptor(name: "skin")
        skin.positions = MeshBuffers.Positions(positions)
        skin.normals = MeshBuffers.Normals(normals)
        skin.primitives = .triangles(indices)
        skin.materials = .allFaces(0)

        // Cut face: an ellipse on the plane x = 0.
        let segments = 48
        var capPositions: [SIMD3<Float>] = [.zero]
        var capNormals: [SIMD3<Float>] = [SIMD3(-1, 0, 0)]
        var capIndices: [UInt32] = []
        for segment in 0...segments {
            let angle = 2 * Float.pi * Float(segment) / Float(segments)
            capPositions.append(SIMD3(0, radius * squash * cos(angle), radius * sin(angle)))
            capNormals.append(SIMD3(-1, 0, 0))
        }
        for segment in 1...segments {
            capIndices += [0, UInt32(segment), UInt32(segment + 1)]
        }
        var cap = MeshDescriptor(name: "cap")
        cap.positions = MeshBuffers.Positions(capPositions)
        cap.normals = MeshBuffers.Normals(capNormals)
        cap.primitives = .triangles(capIndices)
        cap.materials = .allFaces(1)

        return try MeshResource.generate(from: [skin, cap])
    }

    /// The pomegranate's typical crown on top.
    private static func makeCrown(material: PhysicallyBasedMaterial, topY: Float) -> Entity {
        let crown = Entity()
        let base = ModelEntity(mesh: .generateCylinder(height: 0.02, radius: 0.016), materials: [material])
        base.position = SIMD3(0, 0.01, 0)
        crown.addChild(base)
        for tipIndex in 0..<6 {
            let angle = Float(tipIndex) / 6 * 2 * .pi
            let tip = ModelEntity(mesh: .generateBox(width: 0.008, height: 0.018, depth: 0.004), materials: [material])
            tip.position = SIMD3(0.013 * cos(angle), 0.026, 0.013 * sin(angle))
            // Each tip leans outwards.
            tip.orientation = simd_quatf(angle: 0.5, axis: SIMD3(sin(angle), 0, -cos(angle)))
            crown.addChild(tip)
        }
        crown.position = SIMD3(0, topY - 0.004, 0)
        return crown
    }

    private static func material(red: CGFloat, green: CGFloat, blue: CGFloat, roughness: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: red, green: green, blue: blue, alpha: 1))
        material.roughness = .init(floatLiteral: roughness)
        material.faceCulling = .none
        return material
    }

    private static func randomInUnitSphere() -> SIMD3<Float> {
        while true {
            let point = SIMD3<Float>(.random(in: -1...1), .random(in: -1...1), .random(in: -1...1))
            if simd_length(point) <= 1 { return point }
        }
    }
}
