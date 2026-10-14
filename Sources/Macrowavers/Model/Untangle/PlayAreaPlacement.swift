import Foundation
import simd

/// Placement of the play area where the tangled dragon lies, in the immersive space
/// (origin at the player's feet, -Z in front).
struct PlayAreaPlacement: Equatable {
    var position: SIMD3<Float>
    /// Rotation around the vertical axis (radians).
    var yaw: Float
    /// Tilt towards the player (radians): the far edge rises.
    var tilt: Float

    /// Tuned for a seated player: at knee/coffee-table height, slightly tilted.
    static let seated = PlayAreaPlacement(position: SIMD3(0, 0.75, -0.6), yaw: 0, tilt: 15 * .pi / 180)

    static let tiltRange: ClosedRange<Float> = 0...(45 * .pi / 180)

    var rotation: simd_quatf {
        simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: tilt, axis: SIMD3(1, 0, 0))
    }
}
