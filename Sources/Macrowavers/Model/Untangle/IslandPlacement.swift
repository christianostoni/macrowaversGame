import Foundation
import simd

/// Placement of the floating island in the immersive space (origin at the player's feet, -Z in front).
/// The asset's origin is the base of the trunk, on the grass: `position` is where the tree stands, so the grass
/// height is `position.y` whatever the scale (the scale grows the island around the grass, it never moves it).
struct IslandPlacement: Equatable {
    var position: SIMD3<Float>
    /// Rotation around the vertical axis (radians): the player spins the island like a turntable.
    var yaw: Float
    /// The asset is in "real" metres (island ~2.5 m wide, tree ~1.84 m tall): scaled down for the room.
    var scale: Float

    /// The asset at its real size: island ~2.5 m wide (floating rocks ~3.6 m), 2.8 m from the player, grass at
    /// table height (0.6 m), treetop at ~2.45 m. The rock and its roots below the grass (0.91 m deep) sink into
    /// the real floor: `IslandSceneBuilder` hides what is under the floor with an occluder, so the island seems
    /// to rise out of it.
    static let standard = IslandPlacement(position: SIMD3(0, grassHeight, -2.8), yaw: 0, scale: 1)
    /// Height of the grass above the floor (m).
    static let grassHeight: Float = 0.6
    /// Step of the rotation buttons.
    static let yawStep: Float = .pi / 8

    var rotation: simd_quatf {
        simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
    }

    /// From the island's space (asset metres, origin at the base of the trunk) to the scene's.
    var transform: float4x4 {
        var matrix = float4x4(rotation) * float4x4(diagonal: SIMD4(scale, scale, scale, 1))
        matrix.columns.3 = SIMD4(position, 1)
        return matrix
    }
}

/// The path around the tree plus where the tree is in the scene (the island's rotation, scale and bobbing
/// included). The captive dragon flies in the anchor's space: when the island turns, the dragon turns with it,
/// with no trail left behind in scene space.
struct AnchoredOrbit {
    /// Path in the anchor's space (asset metres, centred on the origin).
    var path: OrbitPath
    var worldFromAnchor: float4x4

    /// Uniform scale of the anchor in the scene.
    var scale: Float {
        let column = worldFromAnchor.columns.0
        return simd_length(SIMD3(column.x, column.y, column.z))
    }
}

/// Path of the captive dragon around the tree: a two-turn torus curve wrapped around the trunk.
/// After one turn radius and height swap, so the body (longer than one turn) coils around the tree
/// without ever crossing itself. The head runs along the curve and the body follows it
/// ("follow the leader" in `DragonFlight`).
struct OrbitPath: Equatable {
    /// Base of the trunk.
    var center = SIMD3<Float>.zero
    /// Mean radius around the trunk.
    var radius: Float = 0.6
    /// How much the radius grows and shrinks between the two turns.
    var radialSwing: Float = 0.12
    /// Mean height above the ground: between the bushes and the canopy.
    var height: Float = 0.32
    /// How much it rises and falls between the two turns.
    var verticalSwing: Float = 0.13
    /// Speed of the head (m/s in scene space: it does not depend on the scale).
    var speed: Float = 0.35

    /// Values for the island asset (base of the trunk = origin, asset metres).
    static let aroundTree = OrbitPath()

    /// The same path in another space: centre moved, sizes scaled (not the speed).
    func placed(at center: SIMD3<Float>, scale: Float) -> OrbitPath {
        var path = self
        path.center = center
        path.radius *= scale
        path.radialSwing *= scale
        path.height *= scale
        path.verticalSwing *= scale
        return path
    }

    /// Point of the path. The curve closes every two turns (4π).
    func point(at angle: Float) -> SIMD3<Float> {
        let half = angle / 2
        let distance = radius + radialSwing * cos(half)
        return center + SIMD3(distance * cos(angle), height + verticalSwing * sin(half), distance * sin(angle))
    }

    /// Angle of the path closest to `point` (picks between the two turns).
    func angle(closestTo point: SIMD3<Float>) -> Float {
        let offset = point - center
        let base = atan2(offset.z, offset.x)
        let other = base + 2 * .pi
        return simd_distance(self.point(at: base), point) <= simd_distance(self.point(at: other), point) ? base : other
    }

    /// Body laid along the path behind the head (index 0 = head), nodes `segmentLength` apart.
    func body(headAngle: Float, count: Int, segmentLength: Float) -> [SIMD3<Float>] {
        var result = [point(at: headAngle)]
        var angle = headAngle
        var previous = result[0]
        var walked: Float = 0
        let step: Float = 0.002
        while result.count < count {
            angle -= step
            let next = point(at: angle)
            let length = simd_distance(previous, next)
            if walked + length >= segmentLength {
                // Exact point at `segmentLength` along the curve: no error piling up towards the tail.
                let fraction = (segmentLength - walked) / max(length, 1e-6)
                let node = simd_mix(previous, next, SIMD3(repeating: fraction))
                result.append(node)
                previous = node
                walked = 0
                angle += step
            } else {
                walked += length
                previous = next
            }
        }
        return result
    }
}
