import CoreGraphics
import RealityKit
import simd
import UIKit

/// Chapter II's shamseh (`Shamseh`) drawn far away in the sky, in front of the dome, in the game's colours
/// (`RidePalette`): its hair-thin strapwork faint at first, a petal glazed for each fruit the dragon eats, its
/// colour from a wheel of the game's colours around the medallion (pulled a little towards the fruit's own), so
/// the finished shamseh reads as one rainbow; a poisoned fruit darkens the last petal for a moment. Once they all
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
    /// A poisoned fruit darkens the last lit petal (how much, towards a sickly dark, and for how long, s).
    static let poisonDarkening: Float = 0.8
    static let poisonColour = SIMD3<Float>(0.05, 0.015, 0.04)
    static let poisonTime: Float = 3
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

    /// `colour` darkened by poison (`sickness` 0...1) and warmed towards gold once complete (`warmth` 0...1).
    static func shown(_ colour: SIMD3<Float>, sickness: Float, warmth: Float) -> SIMD3<Float> {
        let sick = simd_mix(colour, poisonColour, SIMD3(repeating: poisonDarkening * min(max(sickness, 0), 1)))
        return simd_mix(sick, RidePalette.gold, SIMD3(repeating: goldWarmth * min(max(warmth, 0), 1)))
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
    /// The petal darkened by a poisoned fruit, and how long it stays dark (s).
    var poisonedPetal: Int?
    var poisonLeft: Float = 0
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
        poisonLeft = max(poisonLeft - deltaTime, 0)
        shine(shamseh)
    }

    /// A poisoned fruit: the last lit petal darkens for a moment (`shamseh`: the petals lit now).
    mutating func poison(_ shamseh: Shamseh) {
        guard !shamseh.colours.isEmpty else { return }
        poisonedPetal = shamseh.colours.count - 1
        poisonLeft = Self.poisonTime
    }

    /// The light behind the medallion, where it has wandered to, seen through every glass tile; the petals' and the
    /// star's glass darkened by poison or warmed to gold.
    @MainActor
    private func shine(_ shamseh: Shamseh) {
        guard glass != nil else { return }
        let warmth = min((completedFor ?? 0) / Self.celebration, 1)
        let sickness = poisonLeft / Self.poisonTime
        for (index, fruit) in zip(petals.indices, glazes) {
            guard let fruit else { continue }
            let colour = Self.shown(Self.glaze(petal: index, of: fruit, folds: shamseh.folds),
                                    sickness: index == poisonedPetal ? sickness : 0, warmth: warmth)
            Self.setGlaze(colour, of: petals[index])
        }
        Self.setGlaze(Self.shown(RidePalette.dragonBlue, sickness: 0, warmth: warmth), of: star)
        let spot = RideGlass.lightSpot(time: lightTime)
        let light = medallion.convert(position: SIMD3(spot, -RideGlass.depth), to: nil)
        // From the unit disc to metres in the world: the medallion swells and comes at the player.
        let scale = medallion.scale(relativeTo: nil).x
        for tile in [star] + petals + kites {
            guard var material = tile.model?.materials.first as? ShaderGraphMaterial else { continue }
            try? material.setParameter(name: "LightPosition", value: .simd3Float(light))
            try? material.setParameter(name: "HaloRadius", value: .float(RideGlass.haloRadius * scale))
            try? material.setParameter(name: "CoreRadius", value: .float(RideGlass.coreRadius * scale))
            tile.model?.materials = [material]
        }
    }

    /// Sets a glass tile's colour.
    @MainActor
    private static func setGlaze(_ colour: SIMD3<Float>, of tile: ModelEntity) {
        guard var material = tile.model?.materials.first as? ShaderGraphMaterial,
              let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let glaze = CGColor(colorSpace: space, components: [CGFloat(colour.x), CGFloat(colour.y),
                                                                   CGFloat(colour.z), 1]) else { return }
        try? material.setParameter(name: "GlazeColor", value: .color(glaze))
        tile.model?.materials = [material]
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
