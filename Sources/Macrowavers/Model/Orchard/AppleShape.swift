import Foundation
import simd

/// Shape of the spiral-cut apple: the same maths as `AppleSpiral.metal`, used on the CPU to place the stem,
/// the worms and the artifact, and as a fallback when Metal is not available.
///
/// The apple is cut along a helix into `turns` slices. Opening it (0 = closed, 1 = fully open) lifts every
/// slice by `gapPerTurn` per turn, like pulling a spiral-cut apple up by its stem. Its silhouette is the design
/// team's apple (`Apple.usdz`), measured as a body of revolution.
/// Origin at the bottom of the apple, y up, metres.
struct AppleShape: Equatable {
    var height: Float = Self.designHeight
    /// Radius at evenly spaced heights, from the bottom (first) to the top (last); at least two.
    var profile: [Float] = Self.designProfile
    /// Turns that open up.
    var turns: Float = 4
    /// Space between two turns when the apple is fully open.
    var gapPerTurn: Float = 0.05

    /// The design team's apple (`Apple.usdz`): the skin's height and its outer radius every 1/24 of it, printed by
    /// `Assets/Blender/apple/measure_apple_profile.py`. Both poles are kept small: the spiral ends in flat faces
    /// drawn with the flesh.
    static let designHeight: Float = 0.1917
    static let designProfile: [Float] = [
        0.0144, 0.0562, 0.0665, 0.0757, 0.0841, 0.0904, 0.0975, 0.1034,
        0.1084, 0.1124, 0.1159, 0.1184, 0.1199, 0.1204, 0.1203, 0.1198,
        0.1185, 0.1162, 0.1132, 0.1092, 0.1043, 0.0983, 0.0898, 0.0804,
        0.0144,
    ]

    /// Which surface of a slice a point lies on.
    enum Surface: UInt32 {
        /// Top face of the slice (flesh).
        case top = 0
        /// Bottom face of the slice (flesh).
        case bottom = 1
        /// Outer wall (skin).
        case skin = 2
    }

    var pitch: Float { height / (turns + 1) }
    var thetaStart: Float { -2 * .pi }
    var thetaEnd: Float { 2 * .pi * (turns + 1) }
    /// How far the stem rises when the apple is fully open.
    var maxLift: Float { gapPerTurn * turns }
    var maxRadius: Float { profile.max() ?? 0 }
    /// Widest across: the size the orchard gives the apple.
    var width: Float { 2 * maxRadius }

    /// Radius of the apple's profile at height `height`: `profile` interpolated linearly (as in the shader).
    func radius(atHeight height: Float) -> Float {
        guard profile.count > 1 else { return profile.first ?? 0 }
        let along = min(max(height / self.height, 0), 1) * Float(profile.count - 1)
        let index = min(Int(along), profile.count - 2)
        let fraction = along - Float(index)
        return profile[index] + (profile[index + 1] - profile[index]) * fraction
    }

    /// How much the slice at angle `theta` is lifted at `opening`.
    func lift(theta: Float, opening: Float) -> Float {
        let turn = theta / (2 * .pi)
        return opening * gapPerTurn * min(max(turn, 0), turns)
    }

    /// Point of the surface.
    /// - Parameters:
    ///   - theta: angle along the spiral.
    ///   - radial: 0 = axis, 1 = edge (flesh faces).
    ///   - vertical: 0 = bottom, 1 = top of the slice (skin).
    func point(theta: Float, radial: Float, vertical: Float, surface: Surface, opening: Float) -> SIMD3<Float> {
        let turn = theta / (2 * .pi)
        let bottom = min(max(turn * pitch, 0), height)
        let top = min(max((turn + 1) * pitch, 0), height)

        let pointHeight: Float
        let pointRadius: Float
        switch surface {
        case .top:
            pointHeight = top
            pointRadius = radius(atHeight: pointHeight) * radial
        case .bottom:
            pointHeight = bottom
            pointRadius = radius(atHeight: pointHeight) * radial
        case .skin:
            pointHeight = bottom + (top - bottom) * vertical
            pointRadius = radius(atHeight: pointHeight)
        }
        return SIMD3(pointRadius * cos(theta), pointHeight + lift(theta: theta, opening: opening), pointRadius * sin(theta))
    }

    /// Outward normal by finite differences of `point` (same algorithm as the shader).
    func normal(theta: Float, radial: Float, vertical: Float, surface: Surface, opening: Float) -> SIMD3<Float> {
        let step: Float = 0.002
        // On the axis (radial = 0) the derivative degenerates: evaluate a little further out.
        let radialEval = surface == .skin ? radial : max(radial, 0.05)
        let sample = { (theta: Float, radial: Float, vertical: Float) in
            point(theta: theta, radial: radial, vertical: vertical, surface: surface, opening: opening)
        }
        let alongTheta = sample(theta + step, radialEval, vertical) - sample(theta - step, radialEval, vertical)
        let alongOther = surface == .skin
            ? sample(theta, radialEval, vertical + step) - sample(theta, radialEval, vertical - step)
            : sample(theta, radialEval + step, vertical) - sample(theta, radialEval - step, vertical)

        let position = sample(theta, radial, vertical)
        let outward = SIMD3(position.x, 0, position.z)
        var normal = simd_cross(alongTheta, alongOther)
        if simd_length(normal) < 1e-8 {
            // Zero-thickness slice (ends of the spiral).
            normal = switch surface {
            case .top: SIMD3(0, 1, 0)
            case .bottom: SIMD3(0, -1, 0)
            case .skin: simd_length(outward) > 1e-8 ? outward : SIMD3(1, 0, 0)
            }
        }
        normal = simd_normalize(normal)
        // Always pointing out of the slice.
        switch surface {
        case .top where normal.y < 0, .bottom where normal.y > 0:
            normal = -normal
        case .skin where simd_dot(normal, outward) < 0:
            normal = -normal
        default:
            break
        }
        return normal
    }
}
