import RealityKit
import simd
import UIKit

/// Chapter II's shamseh (`Shamseh`) drawn far away in the sky, in front of the dome, in the game's colours
/// (`RidePalette`): its hair-thin strapwork faint at first, each petal glazed in the colour of a fruit the dragon
/// ate; once they all are, the central star lights up in the dragon's blue, the kites and the strapwork are
/// gilded, and the whole medallion swells for a moment. Rays, orbs and a ring of dots circle it like an
/// astrolabe's. It stays where it appeared, over the way ahead at the start of the feast; in the finale the dragon
/// flies into its heart (`approach`).
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

    /// The tiles' glazes: the petals take their fruit's, the star the dragon's blue, the kites the island's teal
    /// (gold once complete), the lines the flowers' pale gold.
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
    /// Where it hangs (radians around the vertical, sky space): over the way ahead when the feast began.
    var heading: Float?
    /// 0...1 as it appears with the feast.
    var shown: Float = 0
    /// Petals already glazed with their fruit's colour; seconds since it was completed (nil before).
    var glazed = 0
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
    init(_ shamseh: Shamseh, airbrush: RideAirbrush?) {
        self.airbrush = airbrush
        pivot = Entity()
        pivot.name = "RideShamseh"
        pivot.isEnabled = false
        let medallion = Entity()
        self.medallion = medallion
        medallion.position = SIMD3(0, 0, -Self.distance)
        medallion.scale = SIMD3(repeating: Self.size)
        pivot.addChild(medallion)

        // Tiles first, then the lines over them (a hair closer, drawn after).
        let sortGroup = ModelSortGroup()
        let materials = (lines: Self.material(RidePalette.paleGold, airbrush: airbrush),
                         blank: Self.material(RidePalette.lilac, airbrush: airbrush),
                         star: Self.material(RidePalette.dragonBlue, airbrush: airbrush),
                         kite: Self.material(RidePalette.teal, airbrush: airbrush))
        func tile(_ shape: Shamseh.Shape, material: any RealityKit.Material) -> ModelEntity {
            let entity = ModelEntity(mesh: Self.mesh(shamseh.fill(shape), name: "ShamsehTile"), materials: [material])
            entity.position = SIMD3(shape.centre, 0)
            entity.components.set(OpacityComponent(opacity: 0))
            entity.components.set(ModelSortGroupComponent(group: sortGroup, order: 0))
            medallion.addChild(entity)
            return entity
        }
        star = tile(shamseh.star, material: materials.star)
        petals = shamseh.petals.map { tile($0, material: materials.blank) }
        kites = shamseh.kites.map { tile($0, material: materials.kite) }
        func lines(_ mesh: Shamseh.Mesh, name: String) -> ModelEntity {
            let entity = ModelEntity(mesh: Self.mesh(mesh, name: name), materials: [materials.lines])
            entity.position.z = 0.003
            entity.components.set(ModelSortGroupComponent(group: sortGroup, order: 1))
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

        while glazed < shamseh.colours.count, glazed < petals.count {
            petals[glazed].model?.materials = [Self.material(Self.glaze(of: shamseh.colours[glazed]),
                                                             airbrush: airbrush)]
            glazed += 1
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
                kites.forEach { $0.model?.materials = [gold] }
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
