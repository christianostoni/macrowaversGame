import Foundation
import simd

/// The light of one moment of the day. Pure values: the RealityKit layer (`TimeOfDaySystem`) turns them into the
/// sun, the sky light and the room's tint. Colours are RGB in 0...1.
struct Daylight: Equatable {
    /// Colour of the sun.
    var sunColor: SIMD3<Float>
    /// Strength of the sun (lux, like `DirectionalLightComponent.intensity`).
    var sunIntensity: Float
    /// Height of the sun above the horizon (radians): low at dawn and sunset, almost overhead at noon.
    var sunElevation: Float
    /// Where the sun is around the player (radians): 0 straight ahead (-Z), negative on the left, positive on
    /// the right. It crosses the sky from left to right during the game.
    var sunAzimuth: Float
    /// Which sky lights the scene: 0 dawn, 1 noon, 2 sunset (`SkyGradient`); in between the two are blended.
    var skyBlend: Float
    /// Exposure of the sky light, in stops (`ImageBasedLightComponent.intensityExponent`).
    var skyExposure: Float
    /// How much the real room still lights the virtual content (1 = only the room, 0 = only our sun and sky).
    var roomLightWeight: Float
    /// Colour the passthrough is multiplied by (white = the room as it is).
    var roomTint: SIMD3<Float>

    /// Unit vector from the scene towards the sun (the light travels the opposite way).
    var towardsSun: SIMD3<Float> {
        SIMD3(sin(sunAzimuth) * cos(sunElevation), sin(sunElevation), -cos(sunAzimuth) * cos(sunElevation))
    }

    /// Linear blend: `fraction` 0 is `self`, 1 is `other`.
    func mixed(with other: Daylight, fraction: Float) -> Daylight {
        // Exactly the moment at the ends (no rounding): the light settles on it.
        if fraction <= 0 { return self }
        if fraction >= 1 { return other }
        func mix(_ from: Float, _ to: Float) -> Float { from + (to - from) * fraction }
        return Daylight(sunColor: simd_mix(sunColor, other.sunColor, SIMD3(repeating: fraction)),
                        sunIntensity: mix(sunIntensity, other.sunIntensity),
                        sunElevation: mix(sunElevation, other.sunElevation),
                        sunAzimuth: mix(sunAzimuth, other.sunAzimuth),
                        skyBlend: mix(skyBlend, other.skyBlend),
                        skyExposure: mix(skyExposure, other.skyExposure),
                        roomLightWeight: mix(roomLightWeight, other.roomLightWeight),
                        roomTint: simd_mix(roomTint, other.roomTint, SIMD3(repeating: fraction)))
    }
}

/// Time passing during the game: one clock from dawn (0) to sunset (1), driven by the story. Gathering the
/// ingredients is the morning, untangling the dragon is noon, its farewell is the sunset. The clock never jumps:
/// it runs towards the moment the game is at (`advance`), and the light is read along it (`daylight(at:)`).
enum TimeOfDay {
    /// The moments of the day the light passes through, in order.
    enum Moment: CaseIterable {
        case dawn, morning, noon, goldenHour, sunset

        /// Where the moment sits on the clock.
        var clock: Float {
            switch self {
            case .dawn: 0
            case .morning: 0.25
            case .noon: 0.5
            case .goldenHour: 0.8
            case .sunset: 1
            }
        }

        var daylight: Daylight {
            switch self {
            case .dawn:
                // Warm, low on the left, soft: the room dimmed and tinted peach, like the first light.
                Daylight(sunColor: SIMD3(1, 0.62, 0.42), sunIntensity: 900, sunElevation: radians(8),
                         sunAzimuth: radians(-65), skyBlend: 0, skyExposure: -0.6, roomLightWeight: 0.45,
                         roomTint: SIMD3(0.9, 0.72, 0.62))
            case .morning:
                Daylight(sunColor: SIMD3(1, 0.85, 0.7), sunIntensity: 1500, sunElevation: radians(30),
                         sunAzimuth: radians(-40), skyBlend: 0.5, skyExposure: -0.4, roomLightWeight: 0.5,
                         roomTint: SIMD3(1, 0.88, 0.74))
            case .noon:
                // White, almost overhead: short, sharp shadows. The room at its brightest, a sunny yellow.
                Daylight(sunColor: SIMD3(1, 0.98, 0.94), sunIntensity: 1800, sunElevation: radians(72),
                         sunAzimuth: radians(0), skyBlend: 1, skyExposure: -0.2, roomLightWeight: 0.6,
                         roomTint: SIMD3(1, 0.96, 0.84))
            case .goldenHour:
                Daylight(sunColor: SIMD3(1, 0.6, 0.3), sunIntensity: 1300, sunElevation: radians(18),
                         sunAzimuth: radians(45), skyBlend: 1.6, skyExposure: -0.5, roomLightWeight: 0.45,
                         roomTint: SIMD3(1, 0.72, 0.48))
            case .sunset:
                // Orange and violet, grazing from the right: long shadows, the room darker and tinted.
                Daylight(sunColor: SIMD3(0.95, 0.42, 0.35), sunIntensity: 700, sunElevation: radians(4),
                         sunAzimuth: radians(65), skyBlend: 2, skyExposure: -0.8, roomLightWeight: 0.4,
                         roomTint: SIMD3(0.8, 0.5, 0.6))
            }
        }

        /// The moment closest to `clock` (for the debug panel).
        static func nearest(to clock: Float) -> Moment {
            allCases.min { abs($0.clock - clock) < abs($1.clock - clock) } ?? .dawn
        }
    }

    /// Clock units per second when the day moves on: dawn to noon in ~6 s, about the dragon's flight to the player.
    static let forwardSpeed: Float = 0.08
    /// Clock units per second when the day goes back (Restart Scene): quick, it is not part of the story.
    static let rewindSpeed: Float = 0.6

    /// The moment the game is at.
    /// - Parameters:
    ///   - phase: the dragon's chapter.
    ///   - step: the story's screen.
    ///   - ingredients: ingredients found so far: the morning advances with each of them.
    static func target(phase: DragonPhase, step: StoryStep, ingredients: Int) -> Float {
        if step == .farewell { return Moment.sunset.clock }
        switch phase {
        case .captive, .alerted:
            let found = Float(min(max(ingredients, 0), Elixir.ingredientCount)) / Float(Elixir.ingredientCount)
            return Moment.morning.clock * found
        case .approaching, .landing, .untangling:
            return Moment.noon.clock
        case .free:
            return Moment.goldenHour.clock
        case .gone:
            return Moment.sunset.clock
        }
    }

    /// The clock one frame later: towards `target` at a steady pace, never past it.
    static func advance(_ clock: Float, toward target: Float, deltaTime: Float) -> Float {
        let step = (target >= clock ? forwardSpeed : rewindSpeed) * max(deltaTime, 0)
        return abs(target - clock) <= step ? target : clock + (target > clock ? step : -step)
    }

    /// The light at a point of the clock. Between two moments the light eases out of the first and into the next
    /// (smoothstep), so it settles on each moment instead of turning sharply there.
    static func daylight(at clock: Float) -> Daylight {
        let moments = Moment.allCases
        let clock = min(max(clock, 0), 1)
        guard let next = moments.firstIndex(where: { $0.clock >= clock }), next > 0 else {
            return moments[0].daylight
        }
        let from = moments[next - 1]
        let to = moments[next]
        let fraction = (clock - from.clock) / (to.clock - from.clock)
        return from.daylight.mixed(with: to.daylight, fraction: fraction * fraction * (3 - 2 * fraction))
    }
}

/// Degrees to radians, for the sun's angles.
private func radians(_ degrees: Float) -> Float { degrees * .pi / 180 }

/// The sky that lights the scene at dawn, noon and sunset: a gradient from the zenith to the horizon to the
/// ground. The RealityKit layer paints it into an environment map (`ImageBasedLightComponent`).
struct SkyGradient: Equatable {
    var zenith: SIMD3<Float>
    var horizon: SIMD3<Float>
    var ground: SIMD3<Float>

    /// In the order of `Daylight.skyBlend` (0 dawn, 1 noon, 2 sunset).
    static let dawn = SkyGradient(zenith: SIMD3(0.32, 0.36, 0.62), horizon: SIMD3(1, 0.72, 0.55),
                                  ground: SIMD3(0.35, 0.27, 0.24))
    static let noon = SkyGradient(zenith: SIMD3(0.42, 0.64, 0.95), horizon: SIMD3(0.86, 0.92, 0.98),
                                  ground: SIMD3(0.42, 0.44, 0.38))
    static let sunset = SkyGradient(zenith: SIMD3(0.3, 0.2, 0.48), horizon: SIMD3(1, 0.5, 0.28),
                                    ground: SIMD3(0.26, 0.17, 0.2))
    static let all = [dawn, noon, sunset]

    /// Colour seen at `elevation` radians above (positive) or below (negative) the horizon.
    func color(atElevation elevation: Float) -> SIMD3<Float> {
        if elevation >= 0 {
            // The horizon's glow fades quickly upwards.
            let height = sqrt(min(elevation / (.pi / 2), 1))
            return simd_mix(horizon, zenith, SIMD3(repeating: height))
        }
        let depth = min(-elevation / (.pi / 4), 1)
        return simd_mix(horizon, ground, SIMD3(repeating: depth))
    }
}
