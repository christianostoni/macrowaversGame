import Foundation
import simd

/// The flask's liquid filled to any level: the inside of the glass, taken from the profile of the designers' full
/// liquid (a solid of revolution around its vertical axis), up to the level, closed by a flat surface.
///
/// Squashing the full liquid down to the level instead brought its widest part, near its top, down to the flask's
/// round bottom, where the glass is narrower: the liquid stuck out of the glass until it was full again.
struct LiquidVolume {
    struct Mesh {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
    }

    /// Up, and two horizontal axes: `across` × `up` = `toward` (a right-handed frame).
    let up: SIMD3<Float>
    let across: SIMD3<Float>
    let toward: SIMD3<Float>
    /// The vertical axis at the bottom of the liquid.
    let base: SIMD3<Float>
    /// Height of the full liquid.
    let height: Float
    /// The inside of the glass: radius (`y`) at each height of the full liquid's rings of vertices (`x`, from its
    /// bottom), in a straight line from one ring to the next as in its mesh.
    let profile: [SIMD2<Float>]

    /// - Parameters:
    ///   - points: the full liquid's vertices.
    ///   - direction: which way is up, in the points' space.
    init?(points: [SIMD3<Float>], up direction: SIMD3<Float>) {
        guard points.count >= 3, simd_length(direction) > 1e-6 else { return nil }
        let up = simd_normalize(direction)
        let helper: SIMD3<Float> = abs(up.x) < 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 0, 1)
        let across = simd_normalize(helper - up * simd_dot(helper, up))
        let toward = simd_cross(across, up)

        let heights = points.map { simd_dot($0, up) }
        let sides = points.map { SIMD2(simd_dot($0, across), simd_dot($0, toward)) }
        guard let bottom = heights.min(), let top = heights.max(), top - bottom > 1e-5,
              let low = sides.reduce(nil as SIMD2<Float>?, { simd_min($0 ?? $1, $1) }),
              let high = sides.reduce(nil as SIMD2<Float>?, { simd_max($0 ?? $1, $1) }) else { return nil }
        let centre = (low + high) / 2
        let height = top - bottom

        // Vertices at the same height (within 0.1 % of it) form a ring; its widest vertex lies on the glass.
        let tolerance = height * 0.001
        var profile: [SIMD2<Float>] = []
        for (elevation, side) in zip(heights, sides).sorted(by: { $0.0 < $1.0 }) {
            let knot = SIMD2(elevation - bottom, simd_distance(side, centre))
            if let last = profile.last, knot.x - last.x < tolerance {
                profile[profile.count - 1].y = max(last.y, knot.y)
            } else {
                profile.append(knot)
            }
        }
        guard profile.count >= 2 else { return nil }

        self.up = up
        self.across = across
        self.toward = toward
        self.base = across * centre.x + toward * centre.y + up * bottom
        self.height = height
        self.profile = profile
    }

    /// Radius of the inside of the glass `elevation` above the bottom of the liquid.
    func radius(at elevation: Float) -> Float {
        guard let above = profile.firstIndex(where: { $0.x >= elevation }) else { return profile[profile.count - 1].y }
        guard above > 0 else { return profile[0].y }
        let lower = profile[above - 1], upper = profile[above]
        let amount = upper.x > lower.x ? (elevation - lower.x) / (upper.x - lower.x) : 1
        return lower.y + (upper.y - lower.y) * amount
    }

    /// On the axis, where the body is widest: the centre of a round flask, around which the liquid sloshes without
    /// leaving the glass.
    var widestPoint: SIMD3<Float> {
        let widest = profile.max { $0.y < $1.y } ?? .zero
        return base + up * widest.x
    }

    /// The liquid filled to `level` (0…1 of the full liquid): its side along the glass (a ring at each of the full
    /// liquid's rings below the level, so it never cuts across the glass), its bottom and its flat surface, every
    /// face turned outwards.
    func mesh(level: Float, segments: Int = 48) -> Mesh {
        let surface = min(max(level, 0), 1) * height
        var mesh = Mesh()
        guard surface > 1e-5, segments >= 3 else { return mesh }
        let directions = (0..<segments).map { segment in
            let angle = 2 * Float.pi * Float(segment) / Float(segments)
            return across * cos(angle) + toward * sin(angle)
        }
        let elevations = [0] + profile.map(\.x).filter { $0 > 1e-6 && $0 < surface - 1e-6 } + [surface]

        // Side: a ring at each elevation, its normal across the slope of the glass there.
        for (ring, elevation) in elevations.enumerated() {
            let below = elevations[max(ring - 1, 0)], above = elevations[min(ring + 1, elevations.count - 1)]
            let slope = above > below ? (radius(at: above) - radius(at: below)) / (above - below) : 0
            let ringRadius = radius(at: elevation)
            for direction in directions {
                mesh.positions.append(base + up * elevation + direction * ringRadius)
                mesh.normals.append(simd_normalize(direction - up * slope))
            }
        }
        let count = UInt32(segments)
        for ring in 0..<UInt32(elevations.count - 1) {
            for segment in 0..<count {
                let lowLeft = ring * count + segment
                let lowRight = ring * count + (segment + 1) % count
                let highRight = (ring + 1) * count + (segment + 1) % count
                let highLeft = (ring + 1) * count + segment
                mesh.indices += [lowLeft, highRight, lowRight, lowLeft, highLeft, highRight]
            }
        }

        // Bottom and surface: a fan around the axis, facing down and up.
        for (elevation, normal) in [(Float(0), -up), (surface, up)] {
            let capRadius = radius(at: elevation)
            guard capRadius > 1e-5 else { continue }
            let centre = UInt32(mesh.positions.count)
            mesh.positions.append(base + up * elevation)
            mesh.normals.append(normal)
            for direction in directions {
                mesh.positions.append(base + up * elevation + direction * capRadius)
                mesh.normals.append(normal)
            }
            for segment in 0..<count {
                let first = centre + 1 + segment
                let next = centre + 1 + (segment + 1) % count
                mesh.indices += normal == up ? [centre, next, first] : [centre, first, next]
            }
        }
        return mesh
    }
}
