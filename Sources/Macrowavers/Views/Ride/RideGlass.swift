import RealityKit
import simd

/// A test of Persian geometry in the ride sky (`RideGlass.usdz`: lace by `make_glass_sky.py`, materials by
/// `make_glass_material.py`). Over the top of the painted sky, a lace cap in chapter I's look (a rosette, rings of
/// stars and flowers, a net, a scalloped border well above the horizon): low-poly facets, airbrushed, in the night's
/// own dark colours, added to the sky so it is part of it, with glitter twinkling along its edges and hanging from
/// its border; the border rises into a pointed arch over the shamseh so the two never cross (the lace turns to put
/// the arch over it). And the shamseh's tiles made of stained glass, with a light behind the medallion that wanders
/// across it: where it passes, the glass glows in its own colours, like the light through the Nasir al-Mulk's
/// windows.
enum RideGlass {
    static let assetName = "RideGlass"
    static let skyPatternPath = "/RideGlass/Looks/SkyPattern"
    static let shamsehGlassPath = "/RideGlass/Looks/ShamsehGlass"
    /// The lace: between the shamseh (`ShamsehSky.distance`) and the painted sky (`DragonRideSystem.domeRadius`),
    /// and how much of its colour is added to the sky.
    static let patternRadius: Float = 380
    static let patternStrength: Float = 0.6
    /// The light behind the shamseh (unit disc): it circles at `orbit` from the heart, swaying in and out by `sway`,
    /// a turn every `period` seconds; a little behind the glass.
    static let orbit: Float = 0.5
    static let sway: Float = 0.25
    static let period: Float = 30
    static let depth: Float = 0.02
    /// Its halo through the glass and its bright point (unit disc).
    static let haloRadius: Float = 0.4
    static let coreRadius: Float = 0.06
    /// Where the arch over the shamseh is painted (the lace's own space, level), and how fast the lace turns to put
    /// it over the shamseh (1/s).
    static let archDirection = SIMD3<Float>(-1, 0, 0)
    static let turnRate: Float = 1.2
    /// Drawn first of the ride's see-through things: the lanterns, the mountains and the shamseh come over it.
    @MainActor static let sortGroup = ModelSortGroup()

    /// The lace on the inside of a sphere, nil without the asset.
    @MainActor
    static func makePattern() async -> Entity? {
        guard var material = try? await ShaderGraphMaterial(named: skyPatternPath, from: assetName, in: .main) else {
            print("⚠️ \(assetName).usdz not found: the sky without its lace")
            return nil
        }
        material.faceCulling = .front
        try? material.setParameter(name: "Strength", value: .float(patternStrength))
        let pattern = ModelEntity(mesh: .generateSphere(radius: patternRadius), materials: [material])
        pattern.name = "RideSkyPattern"
        pattern.components.set(ModelSortGroupComponent(group: sortGroup, order: 0))
        pattern.orientation = turn(heading: nil)
        return pattern
    }

    /// Turns the lace under `dome` towards its arch's place over the shamseh (`heading`: where the shamseh hangs,
    /// `ShamsehSky.heading`; nil before the feast).
    @MainActor
    static func align(under dome: Entity, heading: Float?, deltaTime: Float) {
        guard let pattern = dome.findEntity(named: "RideSkyPattern") else { return }
        let share = 1 - exp(-turnRate * deltaTime)
        pattern.orientation = simd_slerp(pattern.orientation, turn(heading: heading), share)
    }

    /// The lace's turn (sky space) that puts its arch over the shamseh at `heading` (straight ahead before the
    /// feast, where it will hang).
    static func turn(heading: Float?) -> simd_quatf {
        simd_quatf(angle: heading ?? 0, axis: SIMD3(0, 1, 0)) * simd_quatf(from: archDirection, to: SIMD3(0, 0, -1))
    }

    /// The shamseh's glass, to glaze each tile with (nil without the asset).
    @MainActor
    static func loadShamsehGlass() async -> ShaderGraphMaterial? {
        guard var material = try? await ShaderGraphMaterial(named: shamsehGlassPath, from: assetName, in: .main)
        else { return nil }
        material.faceCulling = .none
        return material
    }

    /// Where the light is behind the shamseh at `time` (unit disc).
    static func lightSpot(time: Float) -> SIMD2<Float> {
        let angle = 2 * .pi * time / period
        // Swaying in and out at another pace, so its path does not repeat every turn.
        let radius = orbit + sway * sin(2 * .pi * time / (period * 0.37))
        return SIMD2(radius * cos(angle), radius * sin(angle))
    }
}
