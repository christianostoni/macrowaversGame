import RealityKit
import simd

/// The night sky's scenery around the ride, in the game's colours (`RidePalette`): Persian lanterns floating in the
/// sky and mountain peaks far below (`RideShapes`, airbrushed by `RideAirbrush`), and a glitter of light wound around
/// the dragon, streaming back as it flies. Lanterns and mountains live in sky space and come back far ahead once left
/// behind.
struct RideScenery {
    /// The lanterns: how many, how far away they come back ahead (m), how big (m tall) and how they bob.
    static let lanternCount = 22
    static let lanternRadius: Float = 90
    static let lanternSize: ClosedRange<Float> = 1.4...2.4
    static let bobHeight: Float = 0.6
    /// The mountains: how many, how far away they come back ahead (m, along the ground), how tall (m) and how far
    /// below the dragon their tops are (m).
    static let mountainCount = 12
    static let mountainRadius: Float = 300
    static let mountainHeight: ClosedRange<Float> = 90...170
    static let mountainDepth: ClosedRange<Float> = 55...110
    /// The glitter (m): wound about the dragon's body (under the player), how long, how many turns, each strand's
    /// distance from the body; the sparks running along each strand, and how fast they run back (a share of the
    /// flight speed).
    static let glitterAxis = SIMD3<Float>(0, -0.55, -3.5)
    static let glitterLength: Float = 14
    static let glitterTurns: Float = 2.2
    static let glitterRadii: [Float] = [1.7, 2.15]
    static let sparksPerStrand = 4
    static let glitterFlow: Float = 0.5

    /// Colour gradients, no outlines. Lanterns: the flowers' gold glowing, through the pomegranate's pink to the
    /// petals' violet at the rims. Mountains: the island's teal grass, lighter to the rims.
    static let lanternRamp: RideAirbrush.Ramp = [
        (RidePalette.paleGold, 0), (RidePalette.gold, 0.35), (RidePalette.pink, 0.7), (RidePalette.violet, 1),
    ]
    static let mountainRamp: RideAirbrush.Ramp = [
        (SIMD3(0, 0.03, 0.03), 0), (SIMD3(0.02, 0.2, 0.16), 0.35), (RidePalette.teal, 0.7), (RidePalette.mint, 1),
    ]
    /// Translucent gradients: the lanterns clear towards their rims, a glow more than an outline; the mountains
    /// fade from their tops down into the dark (object space: the mesh is 100 tall).
    static let lanternTranslucency = RideAirbrush.Translucency(facing: 1, rim: 0.15)
    static let mountainTranslucency = RideAirbrush.Translucency(bottom: 0.03, fade: 10...75)
    /// Each strand's glitter, from its birth to its fade.
    static let glitterColours = [(RidePalette.paleGold, RidePalette.pink), (RidePalette.lilac, RidePalette.mint)]

    /// Under the sky entity: the lanterns and the mountains (faded in with the sky).
    let holder: Entity
    let lanterns: [Entity]
    /// Each lantern's place in the sky before its bobbing, and its own bobbing phase.
    var lanternSpots: [SIMD3<Float>]
    let lanternPhases: [Float]
    let mountains: [Entity]
    /// Under the ride's root: banks with the dragon. Its sparks (with their strand and place along it, 0...1)
    /// leave the glitter behind them.
    let glitter: Entity
    let sparks: [(entity: Entity, strand: Int)]
    var sparkPlaces: [Float]

    @MainActor
    init(airbrush: RideAirbrush) {
        let holder = Entity()
        self.holder = holder
        holder.name = "RideScenery"
        holder.components.set(OpacityComponent(opacity: 0))

        let lanternMesh = Self.resource(RideShapes.lantern(), name: "Lantern")
        var lanternMaterial = airbrush.material(Self.lanternRamp, grainScale: 40, boost: 0.25,
                                                translucency: Self.lanternTranslucency)
        lanternMaterial.faceCulling = .none
        lanterns = (0..<Self.lanternCount).map { _ in
            let lantern = ModelEntity(mesh: lanternMesh, materials: [lanternMaterial])
            lantern.scale = SIMD3(repeating: .random(in: Self.lanternSize) / 1.1)
            lantern.orientation = simd_quatf(angle: .random(in: 0..<(2 * .pi)), axis: SIMD3(0, 1, 0))
            return lantern
        }
        // All around the player at first, not only ahead.
        lanternSpots = (0..<Self.lanternCount).map { _ in
            simd_quatf(angle: .random(in: 0..<(2 * .pi)), axis: SIMD3(0, 1, 0))
                .act(Self.randomLanternSpot(distance: .random(in: 20...Self.lanternRadius)))
        }
        lanternPhases = (0..<Self.lanternCount).map { _ in .random(in: 0..<(2 * .pi)) }
        lanterns.forEach { holder.addChild($0) }

        // A few mountains, cloned (they share their meshes).
        var random = SystemRandomNumberGenerator()
        var mountainMaterial = airbrush.material(Self.mountainRamp, grainScale: 4,
                                                 translucency: Self.mountainTranslucency)
        mountainMaterial.faceCulling = .none
        let shapes = (0..<4).map { index in
            Self.resource(RideShapes.mountain(height: 100, using: &random), name: "Mountain\(index)")
        }
        mountains = (0..<Self.mountainCount).map { index in
            let mountain = ModelEntity(mesh: shapes[index % shapes.count], materials: [mountainMaterial])
            mountain.orientation = simd_quatf(angle: .random(in: 0..<(2 * .pi)), axis: SIMD3(0, 1, 0))
            mountain.scale = SIMD3(repeating: .random(in: Self.mountainHeight) / 100)
            let angle = Float.random(in: 0..<(2 * .pi))
            let distance = Float.random(in: 60...Self.mountainRadius)
            let top = -Float.random(in: Self.mountainDepth)
            mountain.position = SIMD3(distance * sin(angle), top - 100 * mountain.scale.y, -distance * cos(angle))
            return mountain
        }
        mountains.forEach { holder.addChild($0) }

        let glitter = Entity()
        self.glitter = glitter
        glitter.name = "RideGlitter"
        sparks = Self.glitterRadii.indices.flatMap { strand in
            (0..<Self.sparksPerStrand).map { _ in
                let spark = Entity()
                spark.components.set(Self.sparkEmitter(colours: Self.glitterColours[strand % 2]))
                glitter.addChild(spark)
                return (spark, strand)
            }
        }
        sparkPlaces = sparks.indices.map { Float($0 % Self.sparksPerStrand) / Float(Self.sparksPerStrand) }
    }

    /// Moves the scenery with the flight. `daylight`: 0...1 as the sky comes out of the dark; `bank`: the dragon's.
    @MainActor
    mutating func update(ride: DragonRide, daylight: Float, bank: simd_quatf, deltaTime: Float) {
        if daylight >= 1 {
            holder.components.remove(OpacityComponent.self)
        } else {
            holder.components.set(OpacityComponent(opacity: daylight))
        }

        for index in lanterns.indices {
            if simd_length(lanternSpots[index] - ride.position) > Self.lanternRadius {
                lanternSpots[index] = ride.position
                    + ride.orientation.act(Self.randomLanternSpot(distance: Self.lanternRadius * 0.95))
            }
            let bob = Self.bobHeight * sin(ride.time * 0.8 + lanternPhases[index])
            lanterns[index].position = lanternSpots[index] + SIMD3(0, bob, 0)
        }

        let forward = ride.forward
        let heading = atan2(-forward.x, -forward.z)
        for mountain in mountains {
            let offset = mountain.position - ride.position
            // Left behind, or come up too close under a diving dragon.
            let peak = mountain.position.y + 100 * mountain.scale.y
            guard simd_length(SIMD2(offset.x, offset.z)) > Self.mountainRadius
                    || peak > ride.position.y - Self.mountainDepth.lowerBound / 2 else { continue }
            // Far ahead, in a wide fan, its top well below the dragon.
            let angle = heading + Float.random(in: -1.1...1.1)
            let distance = Self.mountainRadius * Float.random(in: 0.75...0.95)
            let top = ride.position.y - Float.random(in: Self.mountainDepth)
            mountain.position = SIMD3(ride.position.x - distance * sin(angle), top - 100 * mountain.scale.y,
                                      ride.position.z - distance * cos(angle))
        }

        // The sparks wind back along their strands, from the dragon's head to past its tail, and start over;
        // the glitter they leave stays where it was shed.
        glitter.orientation = bank
        let run = ride.speed * Self.glitterFlow / Self.glitterLength * deltaTime
        for (index, spark) in sparks.enumerated() {
            var place = sparkPlaces[index] + run
            place -= place.rounded(.down)
            sparkPlaces[index] = place
            let angle = Float(spark.strand) * .pi + 2 * .pi * Self.glitterTurns * place
            let radius = Self.glitterRadii[spark.strand]
            spark.entity.position = Self.glitterAxis
                + SIMD3(radius * cos(angle), radius * sin(angle), Self.glitterLength * place)
            // Fading in and out at the strand's ends; none while the sky is still dark.
            let ends = sin(.pi * place)
            spark.entity.components[ParticleEmitterComponent.self]?.mainEmitter.birthRate = 480 * ends * daylight
        }
    }

    /// Where a lantern appears (ride space), `distance` away: ahead, in a wide fan, mostly around the dragon's
    /// height and a little above, never right on the way.
    static func randomLanternSpot(distance: Float) -> SIMD3<Float> {
        let height = Float.random(in: -14...22)
        let across = max(distance * distance - height * height, 1).squareRoot()
        var angle = Float.random(in: -1.2...1.2)
        if abs(height) < 6, abs(angle) < 0.15 { angle = angle < 0 ? -0.25 : 0.25 }
        return SIMD3(across * sin(angle), height, -across * cos(angle))
    }

    /// Twinkling specks of light left behind as the spark moves: they stay where they were shed, flicker and fade.
    private static func sparkEmitter(colours: (SIMD3<Float>, SIMD3<Float>)) -> ParticleEmitterComponent {
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .sphere
        emitter.emitterShapeSize = SIMD3(repeating: 0.08)
        emitter.particlesInheritTransform = false
        emitter.emissionDirection = SIMD3(0, 0, 1)
        emitter.speed = 0.08
        emitter.speedVariation = 0.06
        emitter.mainEmitter.birthRate = 0
        emitter.mainEmitter.lifeSpan = 1.4
        emitter.mainEmitter.lifeSpanVariation = 0.5
        emitter.mainEmitter.size = 0.026
        emitter.mainEmitter.sizeVariation = 0.014
        emitter.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.2
        emitter.mainEmitter.spreadingAngle = .pi
        emitter.mainEmitter.opacityCurve = .quickFadeInOut
        emitter.mainEmitter.blendMode = .additive
        emitter.mainEmitter.isLightingEnabled = false
        emitter.mainEmitter.color = .evolving(start: .single(RidePalette.uiColor(colours.0)),
                                              end: .single(RidePalette.uiColor(colours.1)))
        return emitter
    }

    @MainActor
    static func resource(_ mesh: RideShapes.Mesh, name: String) -> MeshResource {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(mesh.positions)
        descriptor.normals = MeshBuffers.Normals(mesh.normals)
        descriptor.primitives = .triangles(mesh.indices)
        // The shapes are well formed (`RideShapesTests`); nothing to draw otherwise.
        return (try? MeshResource.generate(from: [descriptor])) ?? .generateSphere(radius: 0)
    }
}
