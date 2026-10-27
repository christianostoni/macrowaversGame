import CoreGraphics
import RealityKit
import simd
import UIKit

/// The game's own colours (linear sRGB), taken from the island's airbrush materials, the dragon's and the fruit's:
/// everything the ride builds in code is painted with them.
enum RidePalette {
    /// The slate stones: the night.
    static let night = SIMD3<Float>(0.01, 0.01, 0.03)
    static let slate = SIMD3<Float>(0.18, 0.15, 0.32)
    /// The flowers' petals, and their rims.
    static let violet = SIMD3<Float>(0.36, 0.16, 0.75)
    static let lilac = SIMD3<Float>(0.65, 0.54, 0.86)
    /// The dragon's blue.
    static let dragonBlue = SIMD3<Float>(0.11, 0.1, 1)
    /// The teal grass, and its rims.
    static let teal = SIMD3<Float>(0.03, 0.55, 0.42)
    static let mint = SIMD3<Float>(0.47, 0.75, 0.68)
    /// The tree's canopy.
    static let lime = SIMD3<Float>(0.31, 1, 0.06)
    /// The flowers' hearts, and their rims.
    static let gold = SIMD3<Float>(0.95, 0.75, 0.15)
    static let paleGold = SIMD3<Float>(0.97, 0.86, 0.53)
    /// The purple rocks.
    static let magenta = SIMD3<Float>(0.5, 0.09, 0.3)
    /// The fruit: the pomegranate's flesh, the apple's skin, the banana's.
    static let pink = SIMD3<Float>(0.98, 0.49, 0.81)
    static let red = SIMD3<Float>(1, 0.12, 0.1)
    static let orange = SIMD3<Float>(0.88, 0.5, 0.05)
    static let yellow = SIMD3<Float>(0.94, 1, 0.18)

    /// `colour` for UIKit (sRGB).
    static func uiColor(_ colour: SIMD3<Float>, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat(pow(colour.x, 1 / 2.2)), green: CGFloat(pow(colour.y, 1 / 2.2)),
                blue: CGFloat(pow(colour.z, 1 / 2.2)), alpha: alpha)
    }
}

/// The airbrush look for everything the ride builds in code (lanterns, mountains, the shamseh's tiles): the
/// cloud asset's `Airbrush_Cloud` Shader Graph material (`RideCloud.usdz`), given its own colour ramp and grain.
/// The ramp runs from the surfaces facing the player (position 0) to the rims (1), jittered by grain.
struct RideAirbrush {
    /// A colour ramp: four stops (linear sRGB, position 0...1).
    typealias Ramp = [(colour: SIMD3<Float>, position: Float)]

    /// A translucent gradient over the colours (`make_cloud_asset.py`): the opacity of the faces seen straight on
    /// and of the rims, and towards the bottom, fading from `bottom` at the low end of `fade` to opaque at its high
    /// end (object space, y). Sprayed with the same grain as the colours.
    struct Translucency {
        var facing: Float = 1
        var rim: Float = 1
        var bottom: Float = 1
        var fade: ClosedRange<Float> = 0...1

        static let opaque = Translucency()
    }

    let base: ShaderGraphMaterial

    /// The cloud's material, nil when the asset has none.
    @MainActor
    init?(cloud: Entity) {
        guard let material = Self.firstMaterial(in: cloud) else { return nil }
        base = material
    }

    /// The material with `ramp`; `grainScale`: grain cells per metre of the mesh (smaller far away), `boost`
    /// brightens (+) or darkens (-) the faces turned to the player.
    func material(_ ramp: Ramp, grainScale: Float, boost: Float = 0,
                  translucency: Translucency = .opaque) -> ShaderGraphMaterial {
        var material = base
        Self.apply(ramp, to: &material)
        try? material.setParameter(name: "GrainScale", value: .float(grainScale))
        try? material.setParameter(name: "EmissionBoost", value: .float(boost))
        for (name, value) in [("FacingOpacity", translucency.facing), ("RimOpacity", translucency.rim),
                              ("BottomOpacity", translucency.bottom), ("FadeBottom", translucency.fade.lowerBound),
                              ("FadeTop", translucency.fade.upperBound)] {
            try? material.setParameter(name: name, value: .float(value))
        }
        return material
    }

    /// Lights up every airbrush material under `entity` (the dragon in the night sky): `boost` for the faces seen
    /// straight on (the dragon's own is -1.2, almost dark), `base` for all.
    @MainActor
    static func brighten(_ entity: Entity, boost: Float, base: Float) {
        if var model = entity.components[ModelComponent.self] {
            model.materials = model.materials.map { material in
                guard var airbrush = material as? ShaderGraphMaterial else { return material }
                try? airbrush.setParameter(name: "EmissionBoost", value: .float(boost))
                try? airbrush.setParameter(name: "EmissionBase", value: .float(base))
                return airbrush
            }
            entity.components.set(model)
        }
        entity.children.forEach { brighten($0, boost: boost, base: base) }
    }

    /// A ramp from a dark `facing` colour to a light `rim`, through `middle`.
    static func ramp(_ facing: SIMD3<Float>, _ middle: SIMD3<Float>, _ rim: SIMD3<Float>) -> Ramp {
        [(facing, 0), (middle, 0.4), (simd_mix(middle, rim, SIMD3(repeating: 0.5)), 0.7), (rim, 1)]
    }

    /// An almost flat ramp around `colour`: only the grain speckles it (flat shapes facing the player).
    static func glaze(_ colour: SIMD3<Float>) -> Ramp {
        [(colour * 0.78, 0), (colour, 0.18), (colour * 1.08, 0.3), (colour * 1.15, 1)]
    }

    private static func apply(_ ramp: Ramp, to material: inout ShaderGraphMaterial) {
        guard let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else { return }
        for (index, stop) in ramp.prefix(4).enumerated() {
            let colour = CGColor(colorSpace: space, components: [CGFloat(stop.colour.x), CGFloat(stop.colour.y),
                                                                  CGFloat(stop.colour.z), 1])
            if let colour {
                try? material.setParameter(name: "Stop\(index)Color", value: .color(colour))
            }
            try? material.setParameter(name: "Stop\(index)Position", value: .float(stop.position))
        }
    }

    @MainActor
    private static func firstMaterial(in entity: Entity) -> ShaderGraphMaterial? {
        if let material = entity.components[ModelComponent.self]?.materials.first as? ShaderGraphMaterial {
            return material
        }
        for child in entity.children {
            if let material = firstMaterial(in: child) { return material }
        }
        return nil
    }
}
