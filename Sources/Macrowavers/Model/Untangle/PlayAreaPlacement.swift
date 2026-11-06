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

    /// The play area on the way to the island seen from `viewer` (scene space): as far from the player as `seated`
    /// is from the origin, at its height and tilt, turned with its far edge towards the island. The island carried
    /// elsewhere, the dragon comes to coil between the player and it, not where the island used to be.
    func facing(island: IslandPlacement, viewer: SIMD3<Float>) -> PlayAreaPlacement {
        let eyes = SIMD2(viewer.x, viewer.z)
        var towardsIsland = SIMD2(island.position.x, island.position.z) - eyes
        if simd_length(towardsIsland) < 1e-3 { towardsIsland = SIMD2(0, -1) }
        let direction = simd_normalize(towardsIsland)
        let reach = simd_length(SIMD2(Self.seated.position.x, Self.seated.position.z))
        var placement = self
        placement.position = SIMD3(eyes.x + direction.x * reach, Self.seated.position.y, eyes.y + direction.y * reach)
        // Yaw 0 has the far edge towards −Z: turned so it points along `direction`.
        placement.yaw = atan2(-direction.x, -direction.y)
        return placement
    }

    var rotation: simd_quatf {
        simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: tilt, axis: SIMD3(1, 0, 0))
    }
}
