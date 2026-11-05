import simd

/// The thin ring of light under the fruit in front of the player: pinch it and slide the pinch round it, and the
/// fruit turns with the hand, about the ring's upright axis, like a turntable.
enum RingTurn {
    /// The angle of `point` round the ring (ring space: +Y its axis), in the same sense as a turn about +Y.
    static func angle(of point: SIMD3<Float>) -> Float {
        atan2(point.x, point.z)
    }

    /// The turn (rad) from one angle round the ring to the next: the short way, across the ±π seam.
    static func turn(from start: Float, to end: Float) -> Float {
        var turn = (end - start).truncatingRemainder(dividingBy: 2 * .pi)
        if turn > .pi { turn -= 2 * .pi }
        if turn < -.pi { turn += 2 * .pi }
        return turn
    }

    /// Where the ring goes for a fruit whose bounds (ring's parent space) are `bounds`: its centre just under the
    /// fruit, `gap` below its lowest point, and its radius a little wider than the fruit (m).
    static func placement(min: SIMD3<Float>, max: SIMD3<Float>, gap: Float = 0.012,
                          margin: Float = 0.015) -> (centre: SIMD3<Float>, radius: Float) {
        let centre = (min + max) / 2
        let extents = max - min
        let radius = Swift.max(extents.x, extents.z) / 2 * 0.85 + margin
        return (SIMD3(centre.x, min.y - gap, centre.z), radius)
    }
}
