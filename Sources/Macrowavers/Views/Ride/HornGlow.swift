import RealityKit
import simd
import UIKit

/// A blue glow over the outer half of the dragon's horns, from their middle to their tips (`HornTips`): where the
/// player takes hold to steer. Two see-through shells over the horns' own faces: a light blue one just over them,
/// stronger towards the tips, and a wider, fainter halo. While the hands are off the horns it breathes, bright;
/// while they hold, it settles to a faint glow.
struct HornGlow {
    /// The glowing stretch of each horn (0 where it leaves the head, 1 its tip), and where it is at full strength.
    static let start: Float = 0.5
    static let full: Float = 0.7
    /// How far the shells stand off the horns' faces (a share of the horns' size).
    static let lift: Float = 0.008
    static let haloLift: Float = 0.025
    /// Colours (linear sRGB): a light blue heart, the dragon's own blue in the halo.
    static let colour = SIMD3<Float>(0.38, 0.66, 1)
    static let haloColour = SIMD3<Float>(0.25, 0.45, 1)
    /// Opacity of each band (the half's first stretch, the rest to the tip, the halo) at full brightness.
    static let startOpacity: Float = 0.4
    static let tipOpacity: Float = 0.7
    static let haloOpacity: Float = 0.2
    /// Brightness while the hands are off the horns (breathing between the two), and while they hold.
    static let free: ClosedRange<Float> = 0.6...1
    static let held: Float = 0.3
    /// How fast it breathes (rad/s) and eases between the two (1/s).
    static let breathing: Float = 2.4
    static let response: Float = 3

    let glow: Entity
    private var brightness: Float = 1

    /// One see-through shell: its triangles of the horns' mesh, how far off them, its colour and opacity.
    private struct Band {
        let indices: [UInt32]
        let lift: Float
        let colour: SIMD3<Float>
        let opacity: Float
    }

    /// The glow, added to the head over the horns' mesh (`StoneDragonRig.hornMesh()`, head space). nil when the mesh
    /// has no two horns.
    @MainActor
    init?(horns: StoneDragonRig.HornMesh) {
        let positions = horns.positions, normals = horns.normals, indices = horns.indices, base = horns.faceTop
        guard positions.count == normals.count,
              let lower = HornTips.triangles(positions: positions, indices: indices, base: base,
                                             along: Self.start...Self.full),
              let upper = HornTips.triangles(positions: positions, indices: indices, base: base,
                                             along: Self.full...1.5),
              !upper.isEmpty else { return nil }
        let low = positions.reduce(SIMD3(repeating: Float.infinity)) { simd_min($0, $1) }
        let high = positions.reduce(SIMD3(repeating: -Float.infinity)) { simd_max($0, $1) }
        let size = simd_length(high - low)
        // The horns are low-poly, each face its own vertices: pushed out along their faces' normals the shells
        // would fall apart into loose facets. Pushed along the normals averaged where the faces meet, they stay
        // whole.
        let outward = HornTips.outward(positions: positions, normals: normals)
        let smooth = Self.smoothNormals(positions: positions, normals: normals.map { $0 * outward },
                                        tolerance: size * 1e-4)

        glow = Entity()
        glow.name = "HornGlow"
        let bands = [
            Band(indices: lower, lift: Self.lift, colour: Self.colour, opacity: Self.startOpacity),
            Band(indices: upper, lift: Self.lift, colour: Self.colour, opacity: Self.tipOpacity),
            Band(indices: lower + upper, lift: Self.haloLift, colour: Self.haloColour, opacity: Self.haloOpacity),
        ]
        for (index, band) in bands.enumerated() where !band.indices.isEmpty {
            var descriptor = MeshDescriptor(name: "HornGlow\(index)")
            descriptor.positions = MeshBuffers.Positions(zip(positions, smooth).map { $0 + $1 * band.lift * size })
            descriptor.normals = MeshBuffers.Normals(smooth)
            descriptor.primitives = .triangles(band.indices)
            guard let mesh = try? MeshResource.generate(from: [descriptor]) else { continue }
            var material = UnlitMaterial(applyPostProcessToneMap: false)
            material.color = .init(tint: RidePalette.uiColor(band.colour))
            material.blending = .transparent(opacity: .init(floatLiteral: band.opacity))
            // Over the horns, and the halo over the heart: nothing behind them hidden by their depth.
            material.writesDepth = false
            // Both sides: the horns' mesh is not wound the way RealityKit's front faces are.
            material.faceCulling = .none
            glow.addChild(ModelEntity(mesh: mesh, materials: [material]))
        }
        horns.head.addChild(glow)
    }

    /// Each vertex's normal averaged with those of every vertex at the same place (within `tolerance`).
    static func smoothNormals(positions: [SIMD3<Float>], normals: [SIMD3<Float>],
                              tolerance: Float) -> [SIMD3<Float>] {
        func key(_ point: SIMD3<Float>) -> SIMD3<Int32> { SIMD3<Int32>((point / tolerance).rounded(.toNearestOrAwayFromZero)) }
        var sums: [SIMD3<Int32>: SIMD3<Float>] = [:]
        for (position, normal) in zip(positions, normals) { sums[key(position), default: .zero] += normal }
        return zip(positions, normals).map { position, normal in
            let sum = sums[key(position)] ?? normal
            return simd_length(sum) > 1e-6 ? simd_normalize(sum) : normal
        }
    }

    @MainActor
    mutating func update(isHolding: Bool, time: Float, deltaTime: Float) {
        let breath = 0.5 + 0.5 * sin(time * Self.breathing)
        let target = isHolding ? Self.held : Self.free.lowerBound + (Self.free.upperBound - Self.free.lowerBound) * breath
        brightness += (target - brightness) * (1 - exp(-deltaTime * Self.response))
        glow.components.set(OpacityComponent(opacity: brightness))
    }
}
