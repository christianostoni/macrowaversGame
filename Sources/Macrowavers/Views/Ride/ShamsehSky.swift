import CoreGraphics
import RealityKit
import simd
import UIKit

/// Chapter II's shamseh (`Shamseh`) drawn far away in the sky, in front of the dome, in the game's colours
/// (`RidePalette`): its hair-thin strapwork faint at first, a petal glazed for each fruit the dragon eats, its
/// colour from a wheel of the game's colours around the medallion (pulled a little towards the fruit's own), so
/// the finished shamseh reads as one rainbow; a petal a poisoned fruit takes back shatters like glass, its shards
/// falling out of the medallion (`shatter`). Once they all
/// are lit, the central star lights up in the dragon's blue, the kites and the strapwork are gilded, the whole
/// glass warms towards gold, and the medallion swells for a moment. Rays, orbs and a ring of dots circle it like an
/// astrolabe's. It stays where it appeared, over the way ahead at the start of the feast; in the finale the dragon
/// flies into its heart (`approach`). The tiles are stained glass (`RideGlass`): a light behind the medallion
/// wanders across it, and the glass glows in its colours where it passes.
struct ShamsehSky {
    /// How far (m, inside the dome), how high over the horizon and how big it looks (radians).
    static let distance: Float = 340
    static let elevation: Float = 0.3
    static let angularRadius: Float = 0.3
    /// The strapwork's and the rays' width (unit disc), and how faint the strapwork is before the first fruit.
    static let strapWidth: Float = 0.0045
    static let rayWidth: Float = 0.003
    static let faintStrap: Float = 0.45
    /// How fast it appears with the feast, and a tile lights up (1/s); how long the medallion swells once complete
    /// (s), and by how much.
    static let appearRate: Float = 0.4
    static let lightRate: Float = 1.2
    static let celebration: Float = 2.5
    static let swell: Float = 0.12
    /// Airbrush grain cells per unit of the disc (it is about 105 m across).
    static let grainScale: Float = 260
    /// Where the medallion ends up in the finale: past the player (m), through its heart.
    static let passedDistance: Float = -12

    /// The petals' colours: a wheel of the game's colours around the medallion, so the finished shamseh reads as one
    /// rainbow whatever order the fruit came in; each petal's fruit only pulls its colour a little (`fruitPull`).
    /// The star is the dragon's blue, the kites the island's teal (gold once complete), the lines pale gold.
    static let wheel: [SIMD3<Float>] = [
        RidePalette.red, RidePalette.orange, RidePalette.yellow, RidePalette.lime,
        RidePalette.teal, RidePalette.dragonBlue, RidePalette.violet, RidePalette.pink,
    ]
    static let fruitPull: Float = 0.2
    /// A petal shattering (s): it cracks (its shards drawn apart, `crackGap`), then they fall out of the medallion
    /// (unit disc: thrown outwards and towards the player, pulled down by `shardFall`, per s²), fading away.
    static let crackTime: Float = 0.18
    static let shatterTime: Float = 1.7
    static let crackGap: Float = 0.86
    static let shardFall: Float = 0.9
    /// Complete, the whole medallion's glass warms towards gold over the celebration (how far).
    static let goldWarmth: Float = 0.7

    /// The colour of petal `index` of `folds`, lit by `fruit`.
    static func glaze(petal index: Int, of fruit: FruitKind, folds: Int) -> SIMD3<Float> {
        let place = (Float(index) + 0.5) / Float(max(folds, 1))
        return simd_mix(wheelColour(at: place), glaze(of: fruit), SIMD3(repeating: fruitPull))
    }

    /// The wheel's colour at `place` (0...1 around the medallion, wrapping), blended between its stops.
    static func wheelColour(at place: Float) -> SIMD3<Float> {
        let turn = (place - place.rounded(.down)) * Float(wheel.count)
        let index = Int(turn) % wheel.count
        let blend = turn - turn.rounded(.down)
        let smooth = blend * blend * (3 - 2 * blend)
        return simd_mix(wheel[index], wheel[(index + 1) % wheel.count], SIMD3(repeating: smooth))
    }

    /// `colour` warmed towards gold once complete (`warmth` 0...1).
    static func shown(_ colour: SIMD3<Float>, warmth: Float) -> SIMD3<Float> {
        simd_mix(colour, RidePalette.gold, SIMD3(repeating: goldWarmth * min(max(warmth, 0), 1)))
    }

    /// The fruit's own colour (it pulls its petal's a little).
    static func glaze(of fruit: FruitKind) -> SIMD3<Float> {
        switch fruit {
        case .apple: RidePalette.red
        case .pomegranate: RidePalette.pink
        case .orange: RidePalette.orange
        case .pineapple: RidePalette.lime
        case .banana: RidePalette.yellow
        }
    }

    /// Turns with the sky, around the player; the medallion hangs from it.
    let pivot: Entity
    let medallion: Entity
    let star: ModelEntity
    let petals: [ModelEntity]
    let kites: [ModelEntity]
    let strapwork: ModelEntity
    let ornaments: ModelEntity
    /// Each petal's glass in shards (`Shamseh.shards`), made with the medallion so nothing is built mid-flight,
    /// hidden until the petal shatters; where each shard sits in the whole petal, and how it flies.
    let shards: [[ModelEntity]]
    let shardSpots: [[SIMD3<Float>]]
    var shardFlights: [[ShardFlight]]
    /// Seconds since each petal shattered (nil while it is not shattering).
    var shatteredFor: [Float?]
    /// The petals lit at the last frame: fewer now, the lost ones shatter.
    var litCount = 0
    /// The airbrush material to glaze the tiles with (flat unlit colours without it).
    let airbrush: RideAirbrush?
    /// The stained glass the tiles are made of (`RideGlass`; airbrushed tiles without it), and the time its light
    /// has wandered behind the medallion (s).
    let glass: ShaderGraphMaterial?
    var lightTime: Float = 0
    /// Where it hangs (radians around the vertical, sky space): over the way ahead when the feast began.
    var heading: Float?
    /// 0...1 as it appears with the feast.
    var shown: Float = 0
    /// The fruit each petal is glazed with (a petal that lost its colour keeps its glaze while it fades); seconds
    /// since it was completed (nil before).
    var glazes: [FruitKind?]
    var completedFor: Float?
    /// 0...1 through the finale's flight into its heart.
    var approach: Float = 0

    /// The medallion has finished swelling: the dragon can fly off into it.
    var isCelebrated: Bool { (completedFor ?? 0) >= Self.celebration }

    /// Where it is seen from the player (sky space, a unit direction); nil before the feast.
    var direction: SIMD3<Float>? {
        heading.map { Self.placement(heading: $0).act(SIMD3(0, 0, -1)) }
    }

    @MainActor
    init(_ shamseh: Shamseh, airbrush: RideAirbrush?, glass: ShaderGraphMaterial? = nil) {
        self.airbrush = airbrush
        self.glass = glass
        pivot = Entity()
        pivot.name = "RideShamseh"
        pivot.isEnabled = false
        let medallion = Entity()
        self.medallion = medallion
        medallion.position = SIMD3(0, 0, -Self.distance)
        medallion.scale = SIMD3(repeating: Self.size)
        pivot.addChild(medallion)

        // Tiles first, then the lines over them (a hair closer, drawn after), both over the sky's lace.
        let sortGroup = RideGlass.sortGroup
        let materials = (lines: Self.material(RidePalette.paleGold, airbrush: airbrush),
                         blank: Self.tileMaterial(RidePalette.lilac, airbrush: airbrush, glass: glass),
                         star: Self.tileMaterial(RidePalette.dragonBlue, airbrush: airbrush, glass: glass),
                         kite: Self.tileMaterial(RidePalette.teal, airbrush: airbrush, glass: glass))
        func tile(_ shape: Shamseh.Shape, material: any RealityKit.Material) -> ModelEntity {
            let entity = ModelEntity(mesh: Self.mesh(shamseh.fill(shape), name: "ShamsehTile"), materials: [material])
            entity.position = SIMD3(shape.centre, 0)
            entity.components.set(OpacityComponent(opacity: 0))
            entity.components.set(ModelSortGroupComponent(group: sortGroup, order: 2))
            medallion.addChild(entity)
            return entity
        }
        star = tile(shamseh.star, material: materials.star)
        petals = shamseh.petals.map { tile($0, material: materials.blank) }
        kites = shamseh.kites.map { tile($0, material: materials.kite) }
        glazes = Array(repeating: nil, count: petals.count)
        func lines(_ mesh: Shamseh.Mesh, name: String) -> ModelEntity {
            let entity = ModelEntity(mesh: Self.mesh(mesh, name: name), materials: [materials.lines])
            entity.position.z = 0.003
            entity.components.set(ModelSortGroupComponent(group: sortGroup, order: 3))
            medallion.addChild(entity)
            return entity
        }
        strapwork = lines(shamseh.strapwork(width: Self.strapWidth), name: "ShamsehStrapwork")
        ornaments = lines(shamseh.ornaments(width: Self.rayWidth), name: "ShamsehOrnaments")

        // Each petal's shards, just in front of its glass, hidden.
        var random = SystemRandomNumberGenerator()
        var shards: [[ModelEntity]] = []
        var spots: [[SIMD3<Float>]] = []
        for petal in shamseh.petals {
            let pieces = Shamseh.shards(of: petal, using: &random)
            spots.append(pieces.map { SIMD3(petal.centre + $0.centre, 0.001) })
            shards.append(pieces.map { piece in
                let shape = Shamseh.Shape(centre: .zero, corners: piece.corners)
                let entity = ModelEntity(mesh: Self.mesh(shamseh.fill(shape), name: "ShamsehShard"),
                                         materials: [materials.blank])
                entity.isEnabled = false
                entity.components.set(ModelSortGroupComponent(group: sortGroup, order: 2))
                medallion.addChild(entity)
                return entity
            })
        }
        self.shards = shards
        shardSpots = spots
        shardFlights = Array(repeating: [], count: shards.count)
        shatteredFor = Array(repeating: nil, count: shards.count)
    }

    /// Hangs it over the way ahead the first time the feast is on, and lights the tiles of `shamseh`.
    @MainActor
    mutating func draw(_ shamseh: Shamseh, ride: DragonRide, isFeasting: Bool, deltaTime: Float) {
        shown = min(max(shown + (isFeasting ? 1 : -1) * Self.appearRate * deltaTime, 0), 1)
        pivot.isEnabled = shown > 0
        guard shown > 0 else { return }

        if heading == nil {
            let forward = ride.forward
            heading = atan2(-forward.x, -forward.z)
        }
        pivot.orientation = ride.orientation.inverse * Self.placement(heading: heading ?? 0)
        pivot.components.set(OpacityComponent(opacity: smoothstep(shown)))

        for (index, fruit) in zip(petals.indices, shamseh.colours) where glazes[index] != fruit {
            let colour = Self.glaze(petal: index, of: fruit, folds: shamseh.folds)
            petals[index].model?.materials = [Self.tileMaterial(colour, airbrush: airbrush, glass: glass)]
            glazes[index] = fruit
        }
        // Petals a poisoned fruit took back shatter (the kites at their sides fade).
        if shamseh.colours.count < litCount {
            for index in shamseh.colours.count..<min(litCount, petals.count) { shatter(index) }
        }
        litCount = shamseh.colours.count
        fly(deltaTime: deltaTime)
        for index in petals.indices {
            let isLit = index < shamseh.colours.count
            light(petals[index], isLit: isLit, deltaTime: deltaTime)
            light(kites[index], isLit: isLit, deltaTime: deltaTime)
        }
        light(star, isLit: shamseh.isComplete, deltaTime: deltaTime)

        var swell: Float = 1
        if shamseh.isComplete {
            if completedFor == nil {
                // Gilded: the lines and the kites.
                let gold = Self.material(RidePalette.gold, airbrush: airbrush)
                [strapwork, ornaments].forEach { $0.model?.materials = [gold] }
                let goldGlass = Self.tileMaterial(RidePalette.gold, airbrush: airbrush, glass: glass)
                kites.forEach { $0.model?.materials = [goldGlass] }
            }
            let time = (completedFor ?? 0) + deltaTime
            completedFor = time
            swell += Self.swell * sin(.pi * min(time / Self.celebration, 1))
        }
        medallion.scale = SIMD3(repeating: Self.size * swell)
        // The finale: it comes at the player (its size in metres stays: it grows in view), through its heart.
        let reach = pow(approach, 2.2)
        medallion.position.z = -(Self.distance + (Self.passedDistance - Self.distance) * reach)
        let filled = Float(shamseh.colours.count) / Float(max(shamseh.folds, 1))
        strapwork.components.set(OpacityComponent(opacity: Self.faintStrap + (1 - Self.faintStrap) * filled))
        lightTime += deltaTime
        shine(shamseh)
    }

    /// The light behind the medallion, where it has wandered to, seen through every glass tile; the petals' and the
    /// star's glass warmed to gold.
    @MainActor
    private func shine(_ shamseh: Shamseh) {
        guard glass != nil else { return }
        let warmth = min((completedFor ?? 0) / Self.celebration, 1)
        // Each tile's glaze (the kites keep theirs), then the light: one material written a tile a frame (each
        // write copies the material and replaces the tile's model, ~20 of them every frame of the feast).
        var colours: [ObjectIdentifier: SIMD3<Float>] = [:]
        for (index, fruit) in zip(petals.indices, glazes) {
            guard let fruit else { continue }
            colours[ObjectIdentifier(petals[index])] = Self.shown(
                Self.glaze(petal: index, of: fruit, folds: shamseh.folds), warmth: warmth)
        }
        colours[ObjectIdentifier(star)] = Self.shown(RidePalette.dragonBlue, warmth: warmth)
        let spot = RideGlass.lightSpot(time: lightTime)
        let light = medallion.convert(position: SIMD3(spot, -RideGlass.depth), to: nil)
        // From the unit disc to metres in the world: the medallion swells and comes at the player.
        let scale = medallion.scale(relativeTo: nil).x
        for tile in [star] + petals + kites {
            guard var material = tile.model?.materials.first as? ShaderGraphMaterial else { continue }
            if let colour = colours[ObjectIdentifier(tile)], let glaze = Self.linearColour(colour) {
                try? material.setParameter(name: "GlazeColor", value: .color(glaze))
            }
            try? material.setParameter(name: "LightPosition", value: .simd3Float(light))
            try? material.setParameter(name: "HaloRadius", value: .float(RideGlass.haloRadius * scale))
            try? material.setParameter(name: "CoreRadius", value: .float(RideGlass.coreRadius * scale))
            tile.model?.materials = [material]
        }
    }

    /// A glass tile's colour, in the glaze's linear space.
    private static func linearColour(_ colour: SIMD3<Float>) -> CGColor? {
        guard let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else { return nil }
        return CGColor(colorSpace: space, components: [CGFloat(colour.x), CGFloat(colour.y), CGFloat(colour.z), 1])
    }

    /// Its size (m, unit disc to the sky).
    private static var size: Float { distance * tan(angularRadius) }

    /// From the sky's axes to the medallion's: turned to `heading`, raised to `elevation`.
    private static func placement(heading: Float) -> simd_quatf {
        simd_quatf(angle: heading, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: elevation, axis: SIMD3(1, 0, 0))
    }

    /// A tile fades in (or out) and swells a little on the way, like a tile set in place.
    @MainActor
    private func light(_ tile: ModelEntity, isLit: Bool, deltaTime: Float) {
        let current = tile.components[OpacityComponent.self]?.opacity ?? 0
        let target: Float = isLit ? 1 : 0
        guard current != target else { return }
        let next = current < target ? min(current + Self.lightRate * deltaTime, 1)
            : max(current - Self.lightRate * deltaTime, 0)
        tile.components.set(OpacityComponent(opacity: next))
        tile.scale = SIMD3(repeating: 1 + 0.8 * next * (1 - next))
    }

    /// A tile of stained glass in `colour`, or its airbrushed glaze without the glass.
    @MainActor
    private static func tileMaterial(_ colour: SIMD3<Float>, airbrush: RideAirbrush?,
                                     glass: ShaderGraphMaterial?) -> any RealityKit.Material {
        guard var material = glass, let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let glaze = CGColor(colorSpace: space, components: [CGFloat(colour.x), CGFloat(colour.y),
                                                                   CGFloat(colour.z), 1]) else {
            return Self.material(colour, airbrush: airbrush)
        }
        try? material.setParameter(name: "GlazeColor", value: .color(glaze))
        try? material.setParameter(name: "GrainScale", value: .float(grainScale))
        return material
    }

    /// The glaze, airbrushed (only the grain speckles a flat tile), or plain without the airbrush material; seen
    /// from both sides.
    @MainActor
    private static func material(_ colour: SIMD3<Float>, airbrush: RideAirbrush?) -> any RealityKit.Material {
        if let airbrush {
            var material = airbrush.material(RideAirbrush.glaze(colour), grainScale: grainScale)
            material.faceCulling = .none
            return material
        }
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: RidePalette.uiColor(colour))
        material.faceCulling = .none
        return material
    }

    @MainActor
    private static func mesh(_ mesh: Shamseh.Mesh, name: String) -> MeshResource {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(mesh.positions.map { SIMD3($0, 0) })
        // Facing the player: the airbrush ramp stays at its facing end.
        descriptor.normals = MeshBuffers.Normals(Array(repeating: SIMD3(0, 0, 1), count: mesh.positions.count))
        descriptor.primitives = .triangles(mesh.indices)
        // A flat shape always makes a mesh; nothing to draw otherwise.
        return (try? MeshResource.generate(from: [descriptor])) ?? .generatePlane(width: 0, height: 0)
    }

    private func smoothstep(_ x: Float) -> Float { x * x * (3 - 2 * x) }
}

// MARK: - Shattering

extension ShamsehSky {
    /// How a shard of a shattered petal flies (unit disc, the medallion's axes).
    struct ShardFlight {
        var velocity: SIMD3<Float>
        var spinAxis: SIMD3<Float>
        var spinRate: Float
    }

    /// Petal `index` breaks like glass: its tile goes at once, its shards take its place in its own glass (the glaze
    /// it shows now), crack apart, then fall out of the medallion, each its own way.
    @MainActor
    mutating func shatter(_ index: Int) {
        let petal = petals[index]
        let glass = petal.model?.materials ?? []
        petal.components.set(OpacityComponent(opacity: 0))
        petal.scale = .one
        var random = SystemRandomNumberGenerator()
        shardFlights[index] = zip(shards[index], shardSpots[index]).map { shard, spot in
            shard.model?.materials = glass
            shard.position = spot
            shard.orientation = simd_quatf(angle: 0, axis: SIMD3(0, 0, 1))
            shard.scale = .one
            shard.components.set(OpacityComponent(opacity: 1))
            shard.isEnabled = true
            // Out from the medallion's heart and from the petal's own, towards the player.
            let outwards = simd_length(SIMD2(spot.x, spot.y)) > 1e-4 ? simd_normalize(SIMD2(spot.x, spot.y)) : .zero
            let fromPetal = spot - petal.position
            let burst = simd_length(fromPetal) > 1e-4 ? simd_normalize(fromPetal) : .zero
            let across = outwards * Float.random(in: 0.1...0.28, using: &random)
            let axis = SIMD3(Float.random(in: -1...1, using: &random), Float.random(in: -1...1, using: &random),
                             Float.random(in: -1...1, using: &random))
            return ShardFlight(velocity: SIMD3(across, Float.random(in: 0.03...0.1, using: &random))
                                   + burst * Float.random(in: 0.05...0.16, using: &random),
                               spinAxis: simd_length(axis) > 1e-3 ? simd_normalize(axis) : SIMD3(0, 0, 1),
                               spinRate: Float.random(in: 3...9, using: &random))
        }
        shatteredFor[index] = 0
    }

    /// The shards of the petals shattering: cracked apart for a moment, then thrown out, falling and spinning,
    /// fading away; hidden once they have.
    @MainActor
    mutating func fly(deltaTime: Float) {
        for index in shatteredFor.indices {
            guard let before = shatteredFor[index] else { continue }
            let time = before + deltaTime
            guard time < Self.shatterTime else {
                shards[index].forEach { $0.isEnabled = false }
                shatteredFor[index] = nil
                continue
            }
            shatteredFor[index] = time
            let flight = max(time - Self.crackTime, 0)
            let fade = 1 - smoothstep(min(max((time / Self.shatterTime - 0.35) / 0.65, 0), 1))
            // Cracking, each shard shrinks about its own centre: the cracks open between them.
            let crack = 1 - (1 - Self.crackGap) * smoothstep(min(time / Self.crackTime, 1))
            for (shard, (spot, motion)) in zip(shards[index], zip(shardSpots[index], shardFlights[index])) {
                shard.position = spot + motion.velocity * flight + SIMD3(0, -0.5 * Self.shardFall, 0) * flight * flight
                shard.orientation = simd_quatf(angle: motion.spinRate * flight, axis: motion.spinAxis)
                shard.scale = SIMD3(repeating: crack)
                shard.components.set(OpacityComponent(opacity: fade))
            }
        }
    }
}
