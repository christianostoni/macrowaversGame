import Foundation
import simd

/// Where the story's subtitles float: a little below wherever the player looks, like visionOS's Live Captions, so
/// they are read without bending the neck (under the scroll, they were). Lazy: the small movements of reading leave
/// them still; a bigger turn of the head makes them glide after the gaze, then settle again.
struct GazeFollow {
    /// The subtitles this far from the eyes (m): in front of the scroll (0.95 m), never inside its paper.
    static let distance: Float = 0.8
    /// This far below the line of sight.
    static let drop: Float = 15 * .pi / 180
    /// The gaze this far from them sets them gliding; they stop this close to it.
    static let startAngle: Float = 12 * .pi / 180
    static let settleAngle: Float = 1.5 * .pi / 180
    /// How fast they glide (1/s).
    static let responsiveness: Float = 4

    /// From the eyes towards the subtitles (unit length; nil before the first update).
    private(set) var direction: SIMD3<Float>?
    private var isGliding = false

    /// A little below the gaze: `forward` turned down by `drop` (unchanged looking straight up or down).
    static func target(forward: SIMD3<Float>) -> SIMD3<Float> {
        let right = simd_cross(forward, SIMD3(0, 1, 0))
        guard simd_length(right) > 1e-3 else { return forward }
        return simd_normalize(simd_quatf(angle: -drop, axis: simd_normalize(right)).act(forward))
    }

    /// Follows the gaze (`forward`, unit length) for one frame; returns where the subtitles are now.
    mutating func update(forward: SIMD3<Float>, deltaTime: Float) -> SIMD3<Float> {
        let target = Self.target(forward: forward)
        guard let current = direction else {
            direction = target
            return target
        }
        let angle = acos(min(max(simd_dot(current, target), -1), 1))
        if angle > Self.startAngle { isGliding = true }
        guard isGliding else { return current }
        if angle < Self.settleAngle { isGliding = false }
        let blend = 1 - exp(-deltaTime * Self.responsiveness)
        let next = simd_normalize(current + (target - current) * blend)
        direction = next
        return next
    }
}
