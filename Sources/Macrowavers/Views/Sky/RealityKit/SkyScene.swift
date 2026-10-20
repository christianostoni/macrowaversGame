import CoreGraphics
import Foundation
import RealityKit
import UIKit

/// Time of day (`TimeOfDay`): lights the island, the dragon and the orchard with a sun and a sky that follow the
/// story, from dawn while the player gathers the ingredients to noon while they untangle the dragon to sunset at
/// its farewell. On the sky's root, which stays still in the room (the sun does not turn with the island).
struct TimeOfDayComponent: Component {
    let untangle: UntangleViewModel
    let orchard: OrchardViewModel
    let story: StoryViewModel
    let sky: SkyViewModel
    /// Directional light: shines along its local -Z, so its +Z points at the sun.
    let sun: Entity
    /// Image-based light: the sky, blended between dawn, noon and sunset.
    let skyLight: Entity
    /// Dawn, noon and sunset skies (`SkyGradient.all`); empty if they could not be made.
    let environments: [EnvironmentResource]
    /// The parts lit by the sky: their room light is turned down so the sun and the sky show.
    let litRoots: [Entity]
    /// The light has been applied once (the first frame, even with the clock still).
    var isApplied = false

    @MainActor
    var target: Float {
        TimeOfDay.target(phase: untangle.phase, step: story.step, ingredients: orchard.elixir.orbitingCount)
    }
}

struct TimeOfDaySystem: System {
    static let query = EntityQuery(where: .has(TimeOfDayComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let deltaTime = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var time = entity.components[TimeOfDayComponent.self] else { continue }
            // The light changes only while the clock runs: nothing to do between two moments of the day.
            guard time.sky.advance(toward: time.target, deltaTime: deltaTime) || !time.isApplied else { continue }
            Self.apply(time.sky.daylight, to: time)
            if !time.isApplied {
                time.isApplied = true
                entity.components.set(time)
            }
        }
    }

    @MainActor
    private static func apply(_ daylight: Daylight, to time: TimeOfDayComponent) {
        var light = time.sun.components[DirectionalLightComponent.self] ?? DirectionalLightComponent()
        light.color = UIColor(red: CGFloat(daylight.sunColor.x), green: CGFloat(daylight.sunColor.y),
                              blue: CGFloat(daylight.sunColor.z), alpha: 1)
        light.intensity = daylight.sunIntensity
        time.sun.components.set(light)
        time.sun.orientation = simd_quatf(from: SIMD3(0, 0, 1), to: daylight.towardsSun)

        guard time.environments.count == SkyGradient.all.count else { return }
        // `skyBlend` 0...2: between dawn and noon, or between noon and sunset.
        let lower = min(max(Int(daylight.skyBlend), 0), time.environments.count - 2)
        let fraction = min(max(daylight.skyBlend - Float(lower), 0), 1)
        time.skyLight.components.set(ImageBasedLightComponent(
            source: .blend(time.environments[lower], time.environments[lower + 1], fraction),
            intensityExponent: daylight.skyExposure))
        let weight = EnvironmentLightingConfigurationComponent(environmentLightingWeight: daylight.roomLightWeight)
        for root in time.litRoots where root.components[EnvironmentLightingConfigurationComponent.self] != weight {
            root.components.set(weight)
        }
    }
}

/// Builds the sun and the sky of the time of day.
enum SkySceneBuilder {
    static let skyName = "Sky"
    static let sunName = "Sun"
    static let skyLightName = "SkyLight"

    /// Size of the painted skies (equirectangular, 2 : 1): a smooth gradient needs very few pixels.
    private static let skyImageSize = (width: 64, height: 32)

    /// - Parameter litRoots: the island, the dragon's play area and the orchard: they receive the sky's light.
    @MainActor
    static func makeSky(untangle: UntangleViewModel, orchard: OrchardViewModel, story: StoryViewModel,
                        sky: SkyViewModel, litRoots: [Entity]) async -> Entity {
        let root = Entity()
        root.name = skyName

        let sun = Entity()
        sun.name = sunName
        sun.components.set(DirectionalLightComponent())
        // Shadows on the island (the tree on the grass, the dragon on the rock): long at dawn and sunset, short
        // and sharp at noon. The real floor keeps the grounding shadows.
        sun.components.set(DirectionalLightComponent.Shadow(shadowProjection: .automatic(maximumDistance: 6),
                                                            depthBias: 1))
        root.addChild(sun)

        let skyLight = Entity()
        skyLight.name = skyLightName
        root.addChild(skyLight)

        var environments: [EnvironmentResource] = []
        for gradient in SkyGradient.all {
            guard let image = makeSkyImage(gradient),
                  let environment = try? await EnvironmentResource(equirectangular: image) else {
                print("⚠️ The time of day's sky could not be made: only the sun and the room light the scene")
                environments = []
                break
            }
            environments.append(environment)
        }
        // Without a sky the room's own light stays as it is.
        let receivers = environments.isEmpty ? [] : litRoots
        for entity in receivers {
            entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: skyLight))
        }

        root.components.set(TimeOfDayComponent(untangle: untangle, orchard: orchard, story: story, sky: sky,
                                               sun: sun, skyLight: skyLight, environments: environments,
                                               litRoots: receivers))
        return root
    }

    /// Paints a sky gradient into an equirectangular image: top row the zenith, middle the horizon, bottom row
    /// the ground.
    private static func makeSkyImage(_ gradient: SkyGradient) -> CGImage? {
        let (width, height) = skyImageSize
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for row in 0..<height {
            let elevation = Float.pi / 2 - Float.pi * (Float(row) + 0.5) / Float(height)
            let color = gradient.color(atElevation: elevation)
            let bytes = [color.x, color.y, color.z].map { UInt8((min(max($0, 0), 1) * 255).rounded()) }
            for column in 0..<width {
                let index = (row * width + column) * 4
                pixels[index] = bytes[0]
                pixels[index + 1] = bytes[1]
                pixels[index + 2] = bytes[2]
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
