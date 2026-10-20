import Foundation
import simd

/// The small ellipse the elixir's ingredients orbit on, in front of the player, and their fusion into the elixir.
/// Pure maths (Foundation + simd): the `OrchardSystem` keeps one, feeds it the player's head every frame and
/// reads where each ingredient is.
///
/// The orbit is not around the player but around a centre `O` close in front of them, so they see all of it
/// at once, clear of their body and hands. It lives in the frame of the player's body: `forward` and `right`
/// come from a yaw `ψ` that follows the head lazily (see `follow`), never from the head's pitch or roll.
///
///     O = eyes + forward · distance + up · (lift − drop)
///     depth = forward · cos β + up · sin β                  (the plane tilted by β, its far side up: facing the eyes)
///     φ = θ + 2π · slot / count                             (evenly spaced, φ = 0 on the far side)
///     P = O + right · a sin φ + depth · b cos φ
///
/// `a` the half-width, `b` the half-depth, `θ` the phase, growing at `ω = 2π / period`. Seen from above the
/// ingredients go round clockwise (far → right → near → left). `lift` is 0, or `roomLift` while a fruit is in
/// front of the player: the orbit then rises above the fruit and its panel, and comes back down afterwards.
struct ElixirOrbit: Equatable {
    struct Settings: Equatable {
        /// Half-width of the ellipse, side to side (m): ±22° at `distance`, inside the comfortable field of view.
        var lateralRadius: Float = 0.24
        /// Half-depth of the ellipse, in its tilted plane (m).
        var depthRadius: Float = 0.14
        /// The centre is this far in front of the eyes (m), measured on the floor plane.
        var distance: Float = 0.6
        /// ... and this far below them (m): ~17° below the line of sight.
        var drop: Float = 0.18
        /// Tilt of the plane, far side up (radians): the player sees the ellipse open, not edge-on.
        var tilt: Float = 35 * .pi / 180
        /// Seconds per turn (~0.13 m/s along the ellipse).
        var period: Float = 9
        /// How fast the centre follows the eyes (1/s).
        var followResponsiveness: Float = 3
        /// The orbit turns with the player only once the head points this far away from its front (radians) ...
        var turnDeadZone: Float = 30 * .pi / 180
        /// ... and stops turning once within this angle.
        var turnSettled: Float = 5 * .pi / 180
        /// How fast the orbit turns with the player (1/s).
        var turnResponsiveness: Float = 2
        /// How much the orbit rises while a fruit is in front of the player (m).
        var roomLift: Float = 0.28
        /// How fast it rises and comes back down (1/s).
        var liftResponsiveness: Float = 4
        /// Extra turns per turn at the end of the fusion: the ingredients whirl faster as they converge.
        var fusionSpin: Float = 3
        /// The elixir's label: this far below the orbit's centre (m), under its near side.
        var hintDrop: Float = 0.2
    }

    var settings = Settings()
    /// The eyes, smoothed.
    private(set) var eyes = SIMD3<Float>.zero
    /// Rotation around the vertical axis of the orbit's front (0 = −Z).
    private(set) var yaw: Float = 0
    /// θ: how far the ingredients have gone round (radians).
    private(set) var phase: Float = 0
    /// How far the orbit is raised out of the way of a fruit (m).
    private(set) var lift: Float = 0
    /// The first reading places the orbit at once; afterwards it eases.
    private(set) var isPlaced = false
    private var isTurning = false

    var forward: SIMD3<Float> { SIMD3(-sin(yaw), 0, -cos(yaw)) }
    var right: SIMD3<Float> { SIMD3(cos(yaw), 0, -sin(yaw)) }
    /// The ellipse's depth axis: forward, tilted up by `tilt`.
    var depth: SIMD3<Float> { forward * cos(settings.tilt) + SIMD3(0, sin(settings.tilt), 0) }

    /// O: the middle of the ellipse. The ingredients fuse here.
    var center: SIMD3<Float> {
        eyes + forward * settings.distance + SIMD3(0, lift - settings.drop, 0)
    }

    /// Where the elixir's label floats: under the orbit (it hides while a fruit is close, so it never rises).
    var hintPoint: SIMD3<Float> {
        eyes + forward * settings.distance - SIMD3(0, settings.drop + settings.hintDrop, 0)
    }

    /// Follows the player's eyes and, lazily, where they face, and moves the ingredients round.
    /// - Parameters:
    ///   - spin: multiplies the angular speed (1 = calm orbit; higher while fusing).
    ///   - makesRoom: a fruit is in front of the player: the orbit rises above it.
    mutating func follow(eyes position: SIMD3<Float>, forward look: SIMD3<Float>, deltaTime: Float,
                         spin: Float = 1, makesRoom: Bool = false) {
        let flat = SIMD2(look.x, look.z)
        let headYaw = simd_length(flat) > 1e-4 ? atan2(-look.x, -look.z) : yaw
        let targetLift = makesRoom ? settings.roomLift : 0
        guard isPlaced else {
            eyes = position
            yaw = headYaw
            lift = targetLift
            isPlaced = true
            return
        }
        eyes += (position - eyes) * (1 - exp(-deltaTime * settings.followResponsiveness))
        lift += (targetLift - lift) * (1 - exp(-deltaTime * settings.liftResponsiveness))
        // Lazy follow: glances (at an ingredient, at a fruit) leave the orbit where it is; a real turn of the body
        // brings it round in front of the player again, without jumps.
        let difference = Self.wrap(headYaw - yaw)
        if abs(difference) > settings.turnDeadZone { isTurning = true }
        if isTurning {
            yaw = Self.wrap(yaw + difference * (1 - exp(-deltaTime * settings.turnResponsiveness)))
            if abs(difference) < settings.turnSettled { isTurning = false }
        }
        phase = (phase + 2 * .pi / settings.period * spin * deltaTime).truncatingRemainder(dividingBy: 4 * .pi)
    }

    /// Where the ingredient in `slot` is on the ellipse. `shrink` (0…1) pulls the ellipse in towards its centre.
    func point(slot: Int, count: Int = Elixir.ingredientCount, shrink: Float = 0) -> SIMD3<Float> {
        let angle = phase + 2 * .pi * Float(slot) / Float(max(count, 1))
        let size = 1 - min(max(shrink, 0), 1)
        return center
            + right * (size * settings.lateralRadius * sin(angle))
            + depth * (size * settings.depthRadius * cos(angle))
    }

    /// The ingredient in `slot` while they fuse (`progress` 0…1): an inward spiral, the ellipse shrinking to its
    /// centre with `e = smootherstep(progress)` (and spinning faster, see `follow`):
    ///
    ///     P_fusion = O + (1 − e) · (right · a sin φ + depth · b cos φ)
    ///
    /// so it leaves the orbit with no jump (e = 0) and all the ingredients meet at `O` (e = 1).
    func fusionPosition(slot: Int, count: Int = Elixir.ingredientCount, progress: Float) -> SIMD3<Float> {
        point(slot: slot, count: count, shrink: Elixir.smootherstep(progress))
    }

    /// Angle in −π…π.
    static func wrap(_ angle: Float) -> Float {
        atan2(sin(angle), cos(angle))
    }
}

/// The elixir's flight to the dragon: a quadratic Bézier arc that rises above the straight line, so it reads as
/// thrown, not slid, and it does not skim the island's grass. The end follows the dragon's head (it moves), the
/// start stays where the elixir was brewed, and it always arrives in `duration`:
///
///     B(t) = (1 − t)² P₀ + 2 (1 − t) t P₁ + t² P₂,    P₁ = (P₀ + P₂) / 2 + up · (0.25 + 0.1 · |P₂ − P₀|)
///
/// with `t` the flight time eased in and out.
struct ElixirFlight: Equatable {
    /// Average speed (m/s).
    static let speed: Float = 1.1
    static let minimumDuration: Float = 0.9

    let start: SIMD3<Float>
    let duration: Float
    private(set) var elapsed: Float = 0

    init(from start: SIMD3<Float>, to target: SIMD3<Float>) {
        self.start = start
        duration = max(simd_distance(start, target) / Self.speed, Self.minimumDuration)
    }

    var progress: Float { min(elapsed / duration, 1) }
    var isArrived: Bool { elapsed >= duration }

    mutating func advance(deltaTime: Float) {
        elapsed += deltaTime
    }

    /// Where the elixir is now, flying to `target`.
    func position(towards target: SIMD3<Float>) -> SIMD3<Float> {
        let time = Elixir.smoothstep(from: 0, to: 1, progress)
        let control = (start + target) / 2 + SIMD3(0, 0.25 + 0.1 * simd_distance(start, target), 0)
        let rest = 1 - time
        return rest * rest * start + 2 * rest * time * control + time * time * target
    }
}
