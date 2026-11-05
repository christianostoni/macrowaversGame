import simd

/// The tips of the dragon's two horns, found on the horns' mesh (head space: +Y up): the highest vertex is one tip,
/// the highest one well away from it (across the head) is the other. Where the player takes hold to steer, so the
/// ride lights the horns' outer halves up (`HornGlow`).
enum HornTips {
    /// The second tip is at least this share of the horns' width away from the first.
    static let apart: Float = 0.4

    /// The two tips, left (−x) first; nil when the mesh has no two separate tops.
    static func find(in points: [SIMD3<Float>]) -> (left: SIMD3<Float>, right: SIMD3<Float>)? {
        guard let first = points.max(by: { $0.y < $1.y }),
              let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(), maxX - minX > 1e-5 else {
            return nil
        }
        let gap = apart * (maxX - minX)
        guard let second = points.filter({ simd_distance($0, first) > gap }).max(by: { $0.y < $1.y }) else {
            return nil
        }
        return first.x < second.x ? (first, second) : (second, first)
    }

    /// +1 when the mesh's normals point out of the horns, −1 when they point in (each vertex against the middle of
    /// its horn's vertices). The stone dragon's are turned in.
    static func outward(positions: [SIMD3<Float>], normals: [SIMD3<Float>]) -> Float {
        guard let tips = find(in: positions), positions.count == normals.count else { return 1 }
        let middle = (tips.left + tips.right) / 2, across = tips.right - tips.left
        let sides = positions.map { simd_dot($0 - middle, across) > 0 }
        let centres = [false, true].map { side in
            let points = zip(positions, sides).filter { $0.1 == side }.map(\.0)
            return points.reduce(.zero, +) / Float(max(points.count, 1))
        }
        var sum: Float = 0
        for index in positions.indices {
            sum += simd_dot(normals[index], positions[index] - centres[sides[index] ? 1 : 0])
        }
        return sum < 0 ? -1 : 1
    }

    /// The triangles (`indices`, three a triangle) of the horns' mesh whose middle lies `along` the way up each
    /// horn, from `base` (the height where it leaves the head, head space) to its tip: 0 there, 1 at the tip. nil
    /// without two tips.
    static func triangles(positions: [SIMD3<Float>], indices: [UInt32], base: Float,
                          along: ClosedRange<Float>) -> [UInt32]? {
        guard let tips = find(in: positions) else { return nil }
        // Each vertex belongs to the horn on its side of the plane between the tips.
        let middle = (tips.left + tips.right) / 2, across = tips.right - tips.left
        var result: [UInt32] = []
        for face in stride(from: 0, to: indices.count - 2, by: 3) {
            let corners = indices[face..<face + 3]
            guard corners.allSatisfy({ Int($0) < positions.count }) else { continue }
            let centre = corners.map { positions[Int($0)] }.reduce(.zero, +) / 3
            let tip = simd_dot(centre - middle, across) > 0 ? tips.right : tips.left
            guard tip.y - base > 1e-6 else { continue }
            if along.contains((centre.y - base) / (tip.y - base)) { result += corners }
        }
        return result
    }
}
