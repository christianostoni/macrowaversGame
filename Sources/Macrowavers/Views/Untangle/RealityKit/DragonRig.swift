import Foundation
import RealityKit
import simd
#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformColor = NSColor
#endif

/// Snapshot of a game frame passed to the rig: everything needed to draw the dragon.
struct DragonFrame {
    /// Positions of the simulation in the dragon's space (index 0 = head).
    var positions: [SIMD3<Float>]
    var mood: DragonMood
    var action: DragonAction?
    var actionProgress: Float
    var restlessness: Float
    var strain: Float
    var time: Float
    /// Point the head looks at when pulled (the node in the player's hand).
    var lookTarget: SIMD3<Float>?
    /// The player's (the knight's) eyes in the dragon's space.
    var viewer: SIMD3<Float>
    /// Present while the dragon flies (around the tree, towards the player, while settling, free).
    var flight: FlightFrame?
}

struct FlightFrame {
    var maneuver: DragonFlight.Maneuver
    var progress: Float
    /// Velocity of the head in the dragon's space.
    var velocity: SIMD3<Float>
    /// Cruising with the player on its back: 0...1, jaws opening for a fruit ahead (`DragonFeast.appetite`).
    var bite: Float = 0
    /// 0...1: just spat out a banana: shakes its head and snorts (`DragonFeast.disgust`).
    var disgust: Float = 0
    /// 0...1: ate a poisoned fruit: coughs smoke from its nostrils, its head heavy (`DragonFeast.sickness`).
    var sickness: Float = 0
    /// 0...1: breathing fire, jaws wide (`DragonFeast.fire`).
    var fire: Float = 0
}

/// The dragon's "skin": how it is drawn. Collisions and physics are separate,
/// so the placeholder can be swapped for the real asset without touching the game logic.
@MainActor
protocol DragonRig: AnyObject {
    var entity: Entity { get }
    /// Receives the colliders (one per node, index = node). A rig can attach its visuals to the
    /// colliders: visionOS's hover effect lights up the children of the entity being looked at.
    func attach(to colliders: [Entity])
    func update(_ frame: DragonFrame, deltaTime: Float)
    /// The nodes the player can grab in the mini-game, with the radius of their grab sphere (m). nil: every node,
    /// the head included, with the default sphere.
    var grabTargets: [Int: Float]? { get }
    /// The middle of the mouth, its +Z the way fire leaves (the ride's long breath of fire starts there). nil: the
    /// rig does not know it.
    var mouth: Entity? { get }
}

extension DragonRig {
    func attach(to colliders: [Entity]) {}
    var grabTargets: [Int: Float]? { nil }
    var mouth: Entity? { nil }
}

enum DragonRigLoader {
    /// Uses the design team's stone dragon when it is in the bundle, otherwise the procedural placeholder.
    @MainActor
    static func load(config: TangleConfig) async -> DragonRig {
        if let stones = await StoneDragonRig.load(config: config) {
            return stones
        }
        return ProceduralDragonRig(config: config)
    }
}

/// "Expressive" pose of the dragon computed every frame. Valid for any rig.
struct DragonPose {
    var headOrientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
    /// How high the head rises on the neck (m) and how much of the body (m) takes part.
    var neckLift: Float = 0.02
    var neckLength: Float = 0.25
    /// 0 = mouth closed, 1 = wide open.
    var jawOpen: Float = 0
    /// 0 = wings folded along the body, 1 = spread.
    var wingFlare: Float = 0
    /// Extra angle of the wing beat (radians).
    var wingFlap: Float = 0
    /// 0...1: smoke from the nostrils.
    var smoke: Float = 0
    /// 0...1: fire from the mouth.
    var fire: Float = 0
    /// Amplitude of the body's sideways wave (m).
    var bodyWave: Float = 0
}

/// "Alive" animations, purely visual: they never touch the simulation, so the puzzle stays the same
/// even when the dragon rears up, sways or spreads its wings. Designed as if facing a real dragon:
/// it keeps an eye on the knight, warns (smoke, growl) before attacking, and its moves have weight.
struct DragonLifeAnimator {
    let config: TangleConfig
    private(set) var pose = DragonPose()

    init(config: TangleConfig) {
        self.config = config
    }

    /// Breathing: a swelling wave running from head to tail.
    func breathScale(node index: Int, time: Float) -> Float {
        1 + 0.06 * sin(time * 2.2 - distance(of: index) * 5)
    }

    /// Distance of a node from the head along the body at rest (m): the animations do not depend on the node count.
    private func distance(of index: Int) -> Float {
        Float(index) * config.segmentLength
    }

    /// Eyelids (1 = open, 0 = closed): one blink every ~3.5 s.
    func eyeOpenness(time: Float) -> Float {
        let phase = time.truncatingRemainder(dividingBy: 3.5)
        return phase < 0.15 ? abs(phase - 0.075) / 0.075 : 1
    }

    /// Positions to draw: simulation + raised neck + wave + a slow shiver when it is about to lose its temper.
    /// No tremble while the player holds it: high-frequency shaking on a grab read as a glitch, not as anger.
    func visualPositions(_ frame: DragonFrame) -> [SIMD3<Float>] {
        let positions = frame.positions
        let shiver: Float = frame.mood == .restless ? 0.003 * frame.restlessness : 0
        return positions.indices.map { index in
            var position = positions[index]
            let along = distance(of: index)
            // The neck rises gradually towards the head.
            let neckWeight = max(0, 1 - along / max(pose.neckLength, 1e-3))
            position.y += pose.neckLift * neckWeight * neckWeight
            // Sideways wave running along the body (snaking).
            if pose.bodyWave > 0 {
                let previous = positions[max(index - 1, 0)]
                let next = positions[min(index + 1, positions.count - 1)]
                var tangent = previous - next
                tangent.y = 0
                if simd_length(tangent) > 1e-5 {
                    let side = simd_normalize(SIMD3(-tangent.z, 0, tangent.x))
                    position += side * pose.bodyWave * sin(frame.time * 9 - along * 9)
                }
            }
            if shiver > 0 {
                // A ripple running down the body (~1.3 Hz), not a per-vertebra buzz.
                position.y += shiver * sin(frame.time * 8 - along * 12)
            }
            return position
        }
    }

    mutating func update(_ frame: DragonFrame, deltaTime: Float) {
        let positions = frame.positions
        guard positions.count > 2 else { return }
        let time = frame.time
        var target = DragonPose()
        target.neckLift = 0.02 + 0.005 * sin(time * 2.2)

        let headBase = positions[0]
        let bodyForward = simd_normalize(headBase - positions[1])
        var look = bodyForward
        var yawOffset: Float = 0
        var pitchOffset: Float = 0
        var responsiveness: Float = 5

        // Current (drawn) position of the head: the gaze starts here.
        let head = headBase + SIMD3(0, pose.neckLift, 0)
        let toward = { (point: SIMD3<Float>) -> SIMD3<Float> in
            let direction = point - head
            return simd_length(direction) > 0.01 ? simd_normalize(direction) : bodyForward
        }

        if let flight = frame.flight {
            responsiveness = 6
            animateFlight(flight, frame: frame, target: &target, look: &look, toward: toward)
        } else {
            switch frame.mood {
            case .calm:
                // Looks around, but every now and then stares at the knight.
                if time.truncatingRemainder(dividingBy: 9) < 3.5 {
                    look = toward(frame.viewer)
                } else {
                    yawOffset = 0.4 * sin(time * 0.6)
                    pitchOffset = 0.1 * sin(time * 0.9)
                }
            case .annoyed:
                // Watches the hand that pulls it; the harder the pull, the more it bares its teeth and tugs back
                // with its head (slowly: a fast shake looked like a glitch).
                if let hand = frame.lookTarget { look = toward(hand) }
                target.neckLift = 0.05
                target.jawOpen = 0.5 * frame.strain
                yawOffset = 0.06 * sin(time * 3) * frame.strain
                responsiveness = 6
            case .restless:
                // Warning: stares at the knight, shakes its head, smoke from the nostrils, growling mouth.
                look = toward(frame.viewer)
                // Fixed frequency: scaling `time` by the restlessness made the shake speed up wildly (its phase
                // grew with the game time).
                yawOffset = 0.3 * sin(time * 9) * frame.restlessness
                target.neckLift = 0.04 + 0.05 * frame.restlessness
                target.smoke = 0.3 + 0.7 * frame.restlessness
                target.jawOpen = 0.25 * frame.restlessness
                target.wingFlare = 0.3 * frame.restlessness
            case .wriggling:
                responsiveness = 8
                animateAction(frame, target: &target, look: &look, pitch: &pitchOffset, toward: toward)
            case .free:
                // Gratitude: head high towards the knight, wings spread and beating slowly.
                look = toward(frame.viewer)
                target.neckLift = 0.12 + 0.02 * sin(time * 4)
                target.neckLength = 0.4
                target.wingFlare = 1
                target.wingFlap = 0.3 * sin(time * 4)
            }
        }

        target.headOrientation = Self.orientation(looking: look) * simd_quatf(angle: yawOffset, axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: pitchOffset, axis: SIMD3(1, 0, 0))

        blend(toward: target, amount: 1 - exp(-deltaTime * responsiveness))
    }

    /// Smooth blend towards the target pose: the dragon has weight, no jerks.
    private mutating func blend(toward target: DragonPose, amount blend: Float) {
        pose.headOrientation = simd_slerp(pose.headOrientation, target.headOrientation, blend)
        pose.neckLift += (target.neckLift - pose.neckLift) * blend
        pose.neckLength += (target.neckLength - pose.neckLength) * blend
        pose.jawOpen += (target.jawOpen - pose.jawOpen) * min(blend * 2, 1)
        pose.wingFlare += (target.wingFlare - pose.wingFlare) * blend
        pose.wingFlap = target.wingFlap
        pose.smoke += (target.smoke - pose.smoke) * blend
        pose.fire = target.fire
        pose.bodyWave += (target.bodyWave - pose.bodyWave) * blend
    }

    /// Pose for each move of the fit of anger.
    private func animateAction(_ frame: DragonFrame, target: inout DragonPose, look: inout SIMD3<Float>,
                               pitch: inout Float, toward: (SIMD3<Float>) -> SIMD3<Float>) {
        let progress = frame.actionProgress
        let time = frame.time
        switch frame.action {
        case .rearUp:
            // Rises, stares at the knight, roars upwards with a burst of fire, then drops back.
            let rise = smoothstep(0, 0.3, progress) * (1 - smoothstep(0.8, 1, progress))
            let roar = smoothstep(0.35, 0.45, progress) * (1 - smoothstep(0.7, 0.8, progress))
            target.neckLift = 0.22 * rise
            target.neckLength = 0.6
            look = toward(frame.viewer)
            pitch = -0.5 * roar
            target.jawOpen = roar
            target.fire = roar
            target.smoke = roar
            target.wingFlare = rise
            target.wingFlap = 0.35 * sin(time * 10) * rise
        case .turn(let angle):
            // The head leads the turn, the body snakes behind.
            look = rotate(toward(frame.positions[0] + (frame.positions[0] - frame.positions[1])), by: angle > 0 ? 0.8 : -0.8)
            target.neckLift = 0.07
            target.wingFlare = 0.35
            target.bodyWave = 0.012
        case .tailLash:
            if let tail = frame.positions.last { look = toward(tail) }
            target.neckLift = 0.06
            target.jawOpen = 0.4 * sin(progress * .pi)
            target.wingFlare = 0.5
            target.bodyWave = 0.008
        case .coil:
            look = toward(frame.positions.reduce(SIMD3<Float>.zero, +) / Float(frame.positions.count))
            target.neckLift = 0.05
            target.wingFlare = 0.3
            target.bodyWave = 0.006
        case nil:
            break
        }
    }

    /// Flight pose: the head follows the path (or looks at the player when it stops in front of them),
    /// the wings beat hard to climb, glide on the way down, fold in a dive.
    private func animateFlight(_ flight: FlightFrame, frame: DragonFrame, target: inout DragonPose,
                               look: inout SIMD3<Float>, toward: (SIMD3<Float>) -> SIMD3<Float>) {
        let time = frame.time
        let speed = simd_length(flight.velocity)
        if speed > 0.05 { look = flight.velocity / speed }
        // In flight the body is already in 3D: no raised neck nor extra wave.
        target.neckLift = 0
        target.neckLength = 0.05
        target.wingFlare = 1
        let climb = speed > 0.05 ? flight.velocity.y / speed : 0

        switch flight.maneuver {
        case .cruise:
            // Beats when climbing, glides when descending.
            let effort = max(0.15, min(1, 0.4 + climb * 1.5))
            target.wingFlap = 0.5 * effort * sin(time * 6)
            // Fed on the wing: jaws open for the fruit ahead; a banana makes it shake its head, snorting; a
            // poisoned fruit makes it cough smoke, its head drooping and swaying; fire opens its jaws wide.
            target.jawOpen = max(0.8 * flight.bite, 0.35 * flight.disgust, 0.3 * flight.sickness, flight.fire)
            target.smoke = max(flight.disgust, flight.sickness)
            target.fire = flight.fire
            let shake = 0.45 * flight.disgust * sin(time * 14) + 0.3 * flight.sickness * sin(time * 5)
            if shake != 0 { look = rotate(look, by: shake) }
            if flight.sickness > 0 { look = simd_normalize(look - SIMD3(0, 0.35 * flight.sickness, 0)) }
        case .hold:
            // Stopped for the elixir: as it slows down it lifts its snout (about 60° up at a standstill) and opens
            // its mouth a little, wings spread and beating slowly, no smoke: the elixir pours over its head.
            let lift = 1 - smoothstep(0.03, 0.3, speed)
            var forward = frame.positions[0] - frame.positions[1]
            forward.y = 0
            let flat = simd_length(forward) > 1e-4 ? simd_normalize(forward) : look
            look = simd_normalize(flat + SIMD3(0, 1.7 * lift, 0))
            target.wingFlap = 0.3 * sin(time * 3)
            target.jawOpen = 0.25 * lift
        case .orbit, .approach, .land:
            animateJourney(flight, frame: frame, target: &target, look: &look, toward: toward)
        }
    }

    /// Pose from the island to the play area: captive, called, settling.
    private func animateJourney(_ flight: FlightFrame, frame: DragonFrame, target: inout DragonPose,
                                look: inout SIMD3<Float>, toward: (SIMD3<Float>) -> SIMD3<Float>) {
        let time = frame.time
        let progress = flight.progress
        switch flight.maneuver {
        case .orbit where frame.mood == .restless:
            // Disturbed: circles faster without taking its eyes off the knight, growls and snorts smoke.
            look = toward(frame.viewer)
            target.wingFlare = 1
            target.wingFlap = 0.6 * sin(time * 8)
            target.jawOpen = 0.3 + 0.15 * sin(time * 5)
            target.smoke = 0.9
        case .orbit:
            // Captive: glides around the tree; now and then it glances at the knight and snorts.
            target.wingFlap = 0.35 * sin(time * 4)
            if time.truncatingRemainder(dividingBy: 10) < 2.5 {
                let glance = look + toward(frame.viewer)
                if simd_length(glance) > 0.01 { look = simd_normalize(glance) }
            }
            target.smoke = 0.3 * max(0, sin(time * 0.7))
        case .approach:
            // Flies towards the knight, then stops to look at them: it is calming down.
            let arrived = smoothstep(0.4, 0.6, progress)
            target.wingFlap = (0.65 - 0.3 * arrived) * sin(time * 7)
            if arrived > 0 { look = toward(frame.viewer) }
        case .land:
            // Settling: the wings fold while the body lies down into the knot.
            let settle = smoothstep(0.2, 1, progress)
            target.wingFlare = 1 - 0.85 * settle
            target.wingFlap = 0.5 * (1 - settle) * sin(time * 6)
        default:
            break
        }
    }

    /// Orientation with the snout (+Z) along `direction`, no roll.
    static func orientation(looking direction: SIMD3<Float>) -> simd_quatf {
        let yaw = atan2(direction.x, direction.z)
        let pitch = -asin(max(-1, min(1, direction.y)))
        return simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
    }

    private func rotate(_ direction: SIMD3<Float>, by angle: Float) -> SIMD3<Float> {
        simd_quatf(angle: angle, axis: SIMD3(0, 1, 0)).act(direction)
    }

    private func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let amount = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return amount * amount * (3 - 2 * amount)
    }
}
