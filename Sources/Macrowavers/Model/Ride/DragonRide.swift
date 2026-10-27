import Foundation
import simd

/// The end of the story: the player rides on the dragon's back, steering it with both hands as if holding its horns.
/// Pure state, no RealityKit: the RealityKit layer (`DragonRideSystem`) feeds it the hands and draws the flight.
///
/// The player never moves: the world flies past them. Everything here is in the *ride space*: origin at the
/// player's eyes when the ride starts, -Z where they were looking, +Y up. The dragon's heading (`yaw`, `pitch`)
/// and position (`position`) are in a fixed "sky" space that starts equal to the ride space.
struct DragonRide {
    /// How the hands steer the dragon (see `Steering.init(left:right:rest:)`).
    struct Steering: Equatable {
        /// -1 = hard left, 1 = hard right.
        var turn: Float = 0
        /// -1 = dive, 1 = climb.
        var climb: Float = 0
        /// 0 = cruising, 1 = full speed.
        var boost: Float = 0

        /// Hands let go: the dragon glides straight and levels out.
        static let level = Steering()

        /// Both hands on the horns (ride space). A hand lower than the other turns towards its side, both raised
        /// above `rest` climb, both lowered dive, both pushed forward speed up.
        init(left: SIMD3<Float>, right: SIMD3<Float>, rest: SIMD3<Float>) {
            let tilt = left.y - right.y
            turn = Self.clamp(tilt / Settings.fullTurnTilt)
            let middle = (left + right) / 2
            climb = Self.clamp((middle.y - rest.y) / Settings.fullClimbRaise)
            boost = max(0, Self.clamp((rest.z - middle.z) / Settings.fullBoostReach))
            // A small dead zone: hands held still never drift the flight.
            turn = Self.deadZone(turn)
            climb = Self.deadZone(climb)
        }

        init(turn: Float = 0, climb: Float = 0, boost: Float = 0) {
            self.turn = turn
            self.climb = climb
            self.boost = boost
        }

        /// Without hand tracking (the simulator): the dragon swings gently left and right on its own.
        static func autopilot(time: Float) -> Steering {
            Steering(turn: 0.45 * sin(time * 0.35), climb: 0.25 * sin(time * 0.23 + 1), boost: 0)
        }

        private static func clamp(_ value: Float) -> Float { min(max(value, -1), 1) }

        private static func deadZone(_ value: Float) -> Float {
            let zone = Settings.deadZone
            guard abs(value) > zone else { return 0 }
            return (value - zone * (value > 0 ? 1 : -1)) / (1 - zone)
        }
    }

    enum Settings {
        /// Hand height difference (m) for a full turn, and the turn rate it gives (rad/s).
        static let fullTurnTilt: Float = 0.22
        static let maxTurnRate: Float = 0.6
        /// Raise or lower of both hands (m) for a full climb or dive, and the pitch it gives (rad).
        static let fullClimbRaise: Float = 0.2
        static let maxPitch: Float = 0.4
        /// Push forward of both hands (m) for full speed.
        static let fullBoostReach: Float = 0.2
        static let deadZone: Float = 0.12
        /// Cruising and full speed (m/s).
        static let cruiseSpeed: Float = 3
        static let boostSpeed: Float = 6.5
        /// How fast the flight follows the hands (1/s): soft, so it never jerks the player's view.
        static let responsiveness: Float = 1.6
        /// The dragon leans into its turns (rad at full turn), drawn on the dragon only: the player's view never rolls.
        static let maxBank: Float = 0.3
        /// A weak dragon (sick, exhausted: `DragonFeast.weakness`) loses this share of its speed and sways its body
        /// by this much (rad; the body only: the player's view never sways).
        static let weakSlowdown: Float = 0.45
        static let weakSway: Float = 0.22
        /// Where the hands rest on the horns before the player has held them (ride space, m).
        static let defaultRest = SIMD3<Float>(0, -0.35, -0.35)
        /// The dark arrival: a glow comes out of the dark (s), then the dragon appears under the player.
        static let arrivalDuration: Float = 3.5
    }

    // MARK: - State

    /// Heading around +Y (rad): 0 = straight ahead (-Z), positive = turned left.
    private(set) var yaw: Float = 0
    /// Nose up (rad).
    private(set) var pitch: Float = 0
    /// Lean into the turn (rad, positive = right wing down), for the dragon's body only.
    private(set) var bank: Float = 0
    private(set) var speed: Float = Settings.cruiseSpeed
    /// Turn rate (rad/s), smoothed.
    private(set) var turnRate: Float = 0
    /// Where the player is in the sky (m).
    private(set) var position = SIMD3<Float>(repeating: 0)
    /// Seconds since the ride began.
    private(set) var time: Float = 0
    /// Hands' rest position on the horns: taken the first time both hands hold them.
    private(set) var rest: SIMD3<Float>?

    /// 0...1 through the dark arrival; the hands steer only once it is over.
    var arrival: Float { min(time / Settings.arrivalDuration, 1) }
    var isArriving: Bool { arrival < 1 }

    /// Unit direction of flight (sky space).
    var forward: SIMD3<Float> {
        SIMD3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
    }

    /// The sky's rotation seen from the player: from sky space to ride space is its inverse.
    var orientation: simd_quatf {
        simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
    }

    // MARK: - Frame update

    /// Advances the flight. `left`/`right`: the hands in ride space (nil when not tracked); `isHandTrackingAvailable`
    /// false flies the autopilot instead; `weakness` 0...1 slows the dragon down and makes it sway.
    mutating func update(deltaTime: Float, left: SIMD3<Float>?, right: SIMD3<Float>?, isHandTrackingAvailable: Bool,
                         weakness: Float = 0) {
        time += deltaTime
        let steering = steering(left: left, right: right, isHandTrackingAvailable: isHandTrackingAvailable)
        let amount = 1 - exp(-deltaTime * Settings.responsiveness)

        // Right turn = heading turns clockwise seen from above = yaw decreases.
        turnRate += (-steering.turn * Settings.maxTurnRate - turnRate) * amount
        yaw += turnRate * deltaTime
        pitch += (steering.climb * Settings.maxPitch - pitch) * amount
        let sway = Settings.weakSway * weakness * sin(time * 3)
        bank += (steering.turn * Settings.maxBank + sway - bank) * amount
        let targetSpeed = (Settings.cruiseSpeed + steering.boost * (Settings.boostSpeed - Settings.cruiseSpeed))
            * (1 - Settings.weakSlowdown * weakness)
        speed += (targetSpeed - speed) * amount
        position += forward * speed * deltaTime
    }

    func steering(left: SIMD3<Float>?, right: SIMD3<Float>?, isHandTrackingAvailable: Bool) -> Steering {
        guard !isArriving else { return .level }
        guard isHandTrackingAvailable else { return .autopilot(time: time) }
        guard let left, let right else { return .level }
        return Steering(left: left, right: right, rest: rest ?? Settings.defaultRest)
    }

    /// The first time both hands hold the horns (after the arrival) is where they rest: the player's own
    /// comfortable position becomes "straight and level".
    mutating func holdHorns(left: SIMD3<Float>?, right: SIMD3<Float>?) {
        guard rest == nil, !isArriving, let left, let right else { return }
        rest = (left + right) / 2
    }

    /// From sky space to ride space (where the player sits).
    func rideFromSky(_ point: SIMD3<Float>) -> SIMD3<Float> {
        orientation.inverse.act(point - position)
    }

    /// From ride space to sky space.
    func skyFromRide(_ point: SIMD3<Float>) -> SIMD3<Float> {
        position + orientation.act(point)
    }

    // MARK: - The dragon under the player

    /// The dragon's body in ride space, `count` points `spacing` apart from the head (index 0) to the tail. The
    /// player sits `seat` metres behind the head, `seatHeight` above the body. The body follows the flight's
    /// curve (it bends into turns and climbs) and undulates, more towards the tail than under the player.
    func body(count: Int, spacing: Float, seat: Float, seatHeight: Float) -> [SIMD3<Float>] {
        // Curvature of the path (1/m) sideways and upwards: a body following a circle bends into it.
        let sideways = speed > 0.1 ? -turnRate / speed : 0
        let upwards = speed > 0.1 ? pitchRateHint / speed : 0
        return (0..<count).map { index in
            let along = Float(index) * spacing - seat          // < 0 ahead of the player, > 0 behind
            let calm = min(abs(along) / 1.2, 1)                // still under the player, livelier away from them
            let wave = 0.12 * calm * sin(time * 2.4 - along * 1.6)
            let sway = 0.08 * calm * sin(time * 1.3 - along * 1.1)
            return SIMD3(sideways * along * along / 2 + sway,
                         -seatHeight + upwards * along * along / 2 + wave,
                         along)
        }
    }

    /// A hint of the climb for the body's shape: the neck rises ahead when climbing.
    private var pitchRateHint: Float { pitch * 0.6 }
}
