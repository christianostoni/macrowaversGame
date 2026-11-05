import RealityKit
import simd

// The ride's clouds (`RideShapes.cloud`): where they come back ahead (`DragonRideSystem`) and how they are built
// (`DragonRideSceneBuilder`).

extension DragonRideSystem {
    /// Where a cloud appears (ride space), `distance` away: to the sides of the way, around the dragon's height.
    static func randomCloudSpot(distance: Float) -> SIMD3<Float> {
        let side: Float = Bool.random() ? 1 : -1
        let height = Float.random(in: -14...12)
        let angle = side * Float.random(in: cloudAngle)
        let across = max(distance * distance - height * height, 1).squareRoot()
        return SIMD3(across * sin(angle), height, -across * cos(angle))
    }

    /// A cloud upright, its flat face (+z) turned towards `target` (sky space), a little askew.
    static func facing(from position: SIMD3<Float>, to target: SIMD3<Float>) -> simd_quatf {
        let offset = target - position
        return simd_quatf(angle: atan2(offset.x, offset.z) + .random(in: -0.35...0.35), axis: SIMD3(0, 1, 0))
    }
}

extension DragonRideSceneBuilder {
    /// Clouds clean and smooth like the mountains (`RideShapes.cloud`: heaps and puffs), airbrushed like them, a few
    /// shapes shared, scattered around the player, each its own size; they come back facing the way.
    @MainActor
    static func makeClouds(_ airbrush: RideAirbrush) -> [Entity] {
        var random = SystemRandomNumberGenerator()
        var material = airbrush.material(RideScenery.cloudRamp, grainScale: RideScenery.cloudGrain,
                                         translucency: RideScenery.cloudTranslucency)
        material.faceCulling = .back
        // Each shape three times over, each its own lobes, some mirrored.
        let shapes = (0..<6).map { index in
            let shape = RideShapes.CloudShape.allCases[index % 2]
            return RideScenery.resource(RideShapes.cloud(shape, mirrored: index / 2 % 2 == 1, using: &random),
                                        name: "Cloud\(index)")
        }
        return (0..<DragonRideSystem.cloudCount).map { index in
            let cloud = ModelEntity(mesh: shapes[index % shapes.count], materials: [material])
            cloud.name = "RideCloud"
            cloud.components.set(ModelSortGroupComponent(group: RideGlass.sortGroup, order: 1))
            cloud.scale = SIMD3(repeating: .random(in: DragonRideSystem.cloudSize))
            let distance = Float.random(in: 30...DragonRideSystem.cloudRadius)
            // All around the player at first, not only ahead, but never in the middle of the view.
            var spot = DragonRideSystem.randomCloudSpot(distance: distance)
            spot = simd_quatf(angle: .random(in: 0..<(2 * .pi)), axis: SIMD3(0, 1, 0)).act(spot)
            if abs(atan2(spot.x, -spot.z)) < DragonRideSystem.cloudAngle.lowerBound { spot.z = -spot.z }
            cloud.position = spot
            cloud.orientation = DragonRideSystem.facing(from: spot, to: .zero)
            cloud.components.set(OpacityComponent(opacity: 0))
            return cloud
        }
    }
}
