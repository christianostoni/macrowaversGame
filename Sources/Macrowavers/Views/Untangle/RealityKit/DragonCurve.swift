import simd

/// The curve the stone dragon is drawn along: the simulated nodes, smoothed (`StoneDragonRig`).
enum DragonCurve {
    /// Curve points between two simulated nodes: without them the body would follow the polyline's corners.
    static let subdivisions = 4

    /// The head is a rigid piece: if it turns relative to the neck the seam shows. So the first stretch of
    /// neck (`blendLength`, m) leaves the back of the head opposite to the snout and blends gradually into the
    /// simulated body. When the head looks up it rises a little, so the neck does not sink below the play area.
    static func neckFollowingHead(_ points: [SIMD3<Float>], headOrientation: simd_quatf,
                                  blendLength: Float) -> [SIMD3<Float>] {
        guard points.count > 1 else { return points }
        let back = headOrientation.act(SIMD3(0, 0, -1))
        let start = points[0] + SIMD3(0, 0.5 * blendLength * max(0, -back.y), 0)
        var result = points
        result[0] = start
        var travelled: Float = 0
        for index in points.indices.dropFirst() {
            travelled += simd_length(points[index] - points[index - 1])
            guard travelled < blendLength else { break }
            let progress = travelled / blendLength
            let weight = progress * progress * (3 - 2 * progress)
            result[index] = simd_mix(start + back * travelled, points[index], SIMD3(repeating: weight))
        }
        return result
    }

    /// Catmull-Rom spline through the nodes: smooth curves instead of the polyline.
    static func smoothed(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard points.count > 2 else { return points }
        let steps = subdivisions
        var result: [SIMD3<Float>] = []
        result.reserveCapacity((points.count - 1) * steps + 1)
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            // Coefficients of the cubic polynomial of the p1 → p2 stretch.
            let c0 = 2 * p1
            let c1 = p2 - p0
            let c2 = 2 * p0 - 5 * p1 + 4 * p2 - p3
            let c3 = 3 * p1 - p0 - 3 * p2 + p3
            for step in 0..<steps {
                let along = Float(step) / Float(steps)
                result.append(0.5 * (c0 + c1 * along + c2 * (along * along) + c3 * (along * along * along)))
            }
        }
        result.append(points[points.count - 1])
        return result
    }

    /// Point on the polyline at a given distance from the start (extrapolates past the end).
    static func point(on curve: [SIMD3<Float>], atArcLength target: Float) -> SIMD3<Float> {
        var travelled: Float = 0
        for i in 0..<(curve.count - 1) {
            let segment = simd_length(curve[i + 1] - curve[i])
            if travelled + segment >= target, segment > 0 {
                return curve[i] + (curve[i + 1] - curve[i]) * ((target - travelled) / segment)
            }
            travelled += segment
        }
        // Past the end (a stone a little beyond the simulated tail): straight on along the last segment, so it never
        // stacks on the last point.
        guard curve.count > 1 else { return curve.last! }
        let end = curve[curve.count - 1]
        let along = end - curve[curve.count - 2]
        let length = simd_length(along)
        return length > 1e-6 ? end + along / length * (target - travelled) : end
    }
}
