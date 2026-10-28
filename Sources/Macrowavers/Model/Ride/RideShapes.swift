import Foundation
import simd

/// The shapes chapter II's sky is built from, in code: Persian lanterns and the mountain peaks far below. Pure
/// geometry (metres, y up), no RealityKit; `RideScenery` makes meshes of them and gives them the airbrush material,
/// which shades by the normals (facing the player dark, rims light).
enum RideShapes {
    struct Mesh {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        /// Adds `other`, moved by `offset`.
        mutating func append(_ other: Mesh, offset: SIMD3<Float> = .zero) {
            let first = UInt32(positions.count)
            positions += other.positions.map { $0 + offset }
            normals += other.normals
            indices += other.indices.map { $0 + first }
        }
    }

    // MARK: - Lantern

    /// A Persian lantern's outline (radius, height; m, 1.1 m tall): a finial below, a cup, the bulging body, a
    /// collar and an onion dome with its spike.
    static let lanternProfile: [SIMD2<Float>] = [
        SIMD2(0, -0.55), SIMD2(0.05, -0.5), SIMD2(0.03, -0.45), SIMD2(0.12, -0.4), SIMD2(0.2, -0.32),
        SIMD2(0.3, -0.2), SIMD2(0.33, -0.02), SIMD2(0.29, 0.12), SIMD2(0.16, 0.18), SIMD2(0.21, 0.22),
        SIMD2(0.28, 0.27), SIMD2(0.26, 0.35), SIMD2(0.17, 0.42), SIMD2(0.07, 0.47), SIMD2(0.02, 0.5),
        SIMD2(0, 0.56),
    ]

    /// The lantern, low-poly like the island's tree: `sides` flat facets around.
    static func lantern(sides: Int = 8) -> Mesh {
        var mesh = Mesh()
        let profile = lanternProfile
        for ring in 0..<(profile.count - 1) {
            for side in 0..<sides {
                let corners = [(ring, side), (ring, side + 1), (ring + 1, side + 1), (ring + 1, side)].map {
                    lathePoint(profile[$0.0], angle: Float($0.1) / Float(sides) * 2 * .pi)
                }
                // The diagonals' cross product: sound even where a ring shrinks to a point.
                var normal = simd_cross(corners[2] - corners[0], corners[3] - corners[1])
                let centre = corners.reduce(.zero, +) / 4
                if simd_dot(normal, centre - SIMD3(0, centre.y, 0)) < 0 { normal = -normal }
                guard simd_length(normal) > 1e-9 else { continue }
                normal = simd_normalize(normal)
                let first = UInt32(mesh.positions.count)
                mesh.positions += corners
                mesh.normals += Array(repeating: normal, count: 4)
                mesh.indices += [first, first + 1, first + 2, first, first + 2, first + 3]
            }
        }
        return mesh
    }

    // MARK: - Mountains

    /// A round-topped peak, `height` tall from its base at the origin, `radius` wide there: smooth, like the
    /// mountains of Persian and Chinese paintings, rising straight and rounding off at the top.
    static func spire(height: Float, radius: Float, sides: Int = 14, rings: Int = 14) -> Mesh {
        var mesh = Mesh()
        // Rings closer together near the top, where it rounds off.
        let heights = (0...rings).map { height * (1 - pow(1 - Float($0) / Float(rings), 1.6)) }
        for y in heights {
            let rise = min(y / height, 1)
            let shape = 1 - pow(rise, 2.6)
            let ringRadius = radius * pow(max(shape, 0), 0.55)
            // The slope of the outline (dr/dy) tilts the normals up.
            let slope = radius * 0.55 * pow(max(shape, 1e-4), -0.45) * -2.6 * pow(rise, 1.6) / height
            for side in 0...sides {
                let angle = Float(side) / Float(sides) * 2 * .pi
                let around = SIMD3(cos(angle), 0, sin(angle))
                mesh.positions.append(around * ringRadius + SIMD3(0, y, 0))
                mesh.normals.append(simd_normalize(around + SIMD3(0, -max(slope, -50), 0)))
            }
        }
        let row = UInt32(sides + 1)
        for ring in 0..<UInt32(rings) {
            for side in 0..<UInt32(sides) {
                let corner = ring * row + side
                mesh.indices += [corner, corner + row, corner + 1, corner + 1, corner + row, corner + row + 1]
            }
        }
        return mesh
    }

    /// A mountain: a tall peak with smaller ones crowding around and in front of it. Its base is at the origin; its
    /// top `height` above.
    static func mountain(height: Float, using random: inout some RandomNumberGenerator) -> Mesh {
        var mesh = Mesh()
        let radius = height * Float.random(in: 0.18...0.24, using: &random)
        mesh.append(spire(height: height, radius: radius))
        for _ in 0..<Int.random(in: 4...7, using: &random) {
            let share = Float.random(in: 0.3...0.75, using: &random)
            let angle = Float.random(in: 0..<(2 * .pi), using: &random)
            let offset = SIMD3(cos(angle), 0, sin(angle)) * radius * Float.random(in: 0.7...1.6, using: &random)
            mesh.append(spire(height: height * share, radius: radius * Float.random(in: 0.5...0.85, using: &random),
                              sides: 12, rings: 10),
                        offset: offset)
        }
        return mesh
    }
}

private func lathePoint(_ outline: SIMD2<Float>, angle: Float) -> SIMD3<Float> {
    SIMD3(outline.x * cos(angle), outline.y, outline.x * sin(angle))
}
