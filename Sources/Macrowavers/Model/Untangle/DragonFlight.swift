import Foundation
import simd

/// The flying dragon: captive around the tree, coming to the player, settling into the knot and,
/// once free, before flying away.
/// Works in the immersive scene's space (metres, origin at the player's feet, y up).
///
/// The body uses "follow the leader": the head flies and leaves a trail, each vertebra sits on the trail
/// at a fixed distance from the previous one. The body snakes exactly along the head's path,
/// like an eastern dragon, with no physics needed.
final class DragonFlight {
    let settings: Settings
    private(set) var segmentLength: Float
    private(set) var positions: [SIMD3<Float>]
    private(set) var velocity: SIMD3<Float>
    private(set) var maneuver = Maneuver.takeoff
    private(set) var maneuverProgress: Float = 0
    /// Finished the last manoeuvre (`Maneuver.isFinal`): the body stays still.
    private(set) var isFinished = false
    /// Path around the tree, updated every frame (the island bobs).
    var orbit: OrbitPath?
    /// Where it will settle (index 0 = head), in scene space: to set before `.land`.
    var landingKnot: [SIMD3<Float>] = []

    /// Trail of the head: from the oldest point (index 0) to the current head (last).
    private var trail: [SIMD3<Float>]
    private var elapsed: Float = 0
    private var orbitDirection: Float = 1
    private var orbitAngle: Float = 0
    private var maneuverOrigin = SIMD3<Float>.zero
    private var maneuverForward = SIMD3<Float>(0, 0, -1)
    /// Where the player is looking (horizontal, unit length), updated every frame.
    private var viewerForward = SIMD3<Float>(0, 0, -1)
    /// Centre (angle around the player) and phase of the sweep of a cruise in front of them (`Settings.frontArc`).
    private var arcCenter: Float = 0
    private var arcPhase: Float = 0
    /// Where it hovers: eased towards the spot in front of the player's eyes.
    private var hoverSpot = SIMD3<Float>.zero
    private var random = SystemRandomNumberGenerator()
    /// Manoeuvres already decided (script): once they are done, the dragon picks by itself.
    private var plan: [Maneuver] = []
    /// Angle of the head on `orbit`.
    private var pathAngle: Float = 0
    private var approachSpot = SIMD3<Float>.zero
    private var departDirection = SIMD3<Float>(0, 0, -1)
    /// Path of the head while it settles, and how much of it is done.
    private var landingPath: [SIMD3<Float>] = []
    private var landingLength: Float = 0
    private var landingTraveled: Float = 0
    private var landingSegment = 0
    private var landingSegmentStart: Float = 0

    /// `start`: current body positions (index 0 = head) in scene space.
    /// `plan`: manoeuvres to run in order (the first starts at once).
    /// `viewer`, `viewerForward`: the player's eyes and where they look, when known.
    init(start: [SIMD3<Float>], segmentLength: Float, settings: Settings = Settings(),
         plan: [Maneuver] = [.takeoff], orbit: OrbitPath? = nil,
         viewer: SIMD3<Float>? = nil, viewerForward: SIMD3<Float> = SIMD3(0, 0, -1)) {
        self.settings = settings
        self.segmentLength = segmentLength
        self.orbit = orbit
        positions = start
        // The initial trail is the body itself, from tail to head: on take-off the body "unrolls".
        trail = start.reversed()
        let forward = simd_normalize(start[0] - start[1])
        velocity = SIMD3(forward.x, 0.6, forward.z) * 0.3
        orbitDirection = Bool.random(using: &random) ? 1 : -1
        lookAhead(viewerForward)
        perform(plan.isEmpty ? [.takeoff] : plan, viewer: viewer ?? start[0])
    }

    /// Captive on the island: the body is already wrapped around the tree along the path.
    static func captive(on orbit: OrbitPath, nodeCount: Int, segmentLength: Float,
                        settings: Settings = Settings()) -> DragonFlight {
        let start = orbit.body(headAngle: 0, count: nodeCount, segmentLength: segmentLength)
        let flight = DragonFlight(start: start, segmentLength: segmentLength, settings: settings, plan: [.orbit], orbit: orbit)
        // Dense trail along the curve (not the chords between the nodes): the body does not jump on the first frame.
        let bodyAngle = segmentLength * Float(nodeCount + 4) / max(orbit.radius - orbit.radialSwing, 0.05)
        flight.trail = stride(from: -bodyAngle, to: 0, by: 0.01).map(orbit.point(at:)) + [start[0]]
        return flight
    }

    /// Moves the flight into another space (e.g. from the island to the scene when the dragon leaves it).
    /// `matrix` must have a uniform scale: distances, including the one between vertebrae, scale with it.
    func transform(by matrix: float4x4) {
        let column = matrix.columns.0
        let scale = simd_length(SIMD3(column.x, column.y, column.z))
        let point = { (value: SIMD3<Float>) -> SIMD3<Float> in
            let result = matrix * SIMD4(value, 1)
            return SIMD3(result.x, result.y, result.z)
        }
        positions = positions.map(point)
        trail = trail.map(point)
        let direction = matrix * SIMD4(velocity, 0)
        velocity = SIMD3(direction.x, direction.y, direction.z)
        segmentLength *= scale
        orbit = nil
    }

    /// Replaces the script: the first manoeuvre starts at once, from the current position and velocity.
    func perform(_ maneuvers: [Maneuver], viewer: SIMD3<Float>) {
        guard let first = maneuvers.first else { return }
        plan = Array(maneuvers.dropFirst())
        isFinished = false
        begin(first, viewer: viewer)
    }

    /// `viewerForward`: where the player is looking (the farewell stays in front of them).
    func update(deltaTime: Float, viewer: SIMD3<Float>, viewerForward: SIMD3<Float> = SIMD3(0, 0, -1)) {
        guard !isFinished else { return }
        let dt = min(deltaTime, 1.0 / 30.0)
        guard dt > 0 else { return }
        lookAhead(viewerForward)
        elapsed += dt
        maneuverProgress = maneuver == .land ? landingProgress : min(elapsed / maneuver.duration, 1)
        if maneuverProgress >= 1 {
            if maneuver.isFinal && plan.isEmpty {
                isFinished = true
                return
            }
            begin(plan.isEmpty ? nextManeuver() : plan.removeFirst(), viewer: viewer)
        }

        let head: SIMD3<Float>
        switch maneuver {
        case .orbit:
            // Fixed path: the velocity is whatever results (the rig and the next manoeuvre need it).
            head = advanceOnOrbit(dt: dt)
            velocity = (head - positions[0]) / dt
        case .land:
            head = advanceOnLandingPath(dt: dt)
            velocity = (head - positions[0]) / dt
        default:
            head = flyFreely(viewer: viewer, dt: dt)
        }

        if simd_distance(head, trail.last!) > segmentLength * 0.1 { trail.append(head) }
        positions = bodyAlongTrail(head: head)
        trimTrail()
        // Departing, it is over once it has faded out (a couple of metres away, before any wall or ceiling).
        if maneuver == .depart && plan.isEmpty && departFade >= 1 { isFinished = true }
    }

    /// Steered flight (every manoeuvre but the paths): towards the manoeuvre's target, inside the room.
    private func flyFreely(viewer: SIMD3<Float>, dt: Float) -> SIMD3<Float> {
        if maneuver == .hover {
            // Follows the player's gaze slowly: it settles in front of them without chasing every head turn.
            hoverSpot += (hoverTarget(viewer: viewer) - hoverSpot) * (1 - exp(-dt * 1.5))
        }
        steer(toward: target(viewer: viewer), viewer: viewer, dt: dt)
        var head = positions[0] + velocity * dt
        guard maneuver.staysInRoom else { return head }
        // Eased back inside the flight volume: it can never wander out of the room.
        let inside = confined(head, viewer: viewer)
        if inside != head {
            head += (inside - head) * (1 - exp(-dt * 6))
            velocity = (head - positions[0]) / dt
        }
        return head
    }

    /// While departing: 0 = fully visible, 1 = faded out (`Settings.departFade`, by distance travelled).
    var departFade: Float {
        guard maneuver == .depart else { return 0 }
        let range = settings.departFade
        let travelled = simd_distance(positions[0], maneuverOrigin)
        return max(0, min(1, (travelled - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }

    private func lookAhead(_ forward: SIMD3<Float>) {
        let flat = SIMD3(forward.x, 0, forward.z)
        if simd_length(flat) > 1e-3 { viewerForward = simd_normalize(flat) }
    }

    /// Spot in front of the player's eyes, at their height, where it hovers.
    private func hoverTarget(viewer: SIMD3<Float>) -> SIMD3<Float> {
        viewer + viewerForward * settings.hoverDistance
    }

    /// Closest point inside the flight volume: between the personal space and `orbitRadius` (plus the margin)
    /// around the player, within `altitude` (plus the margin).
    private func confined(_ point: SIMD3<Float>, viewer: SIMD3<Float>) -> SIMD3<Float> {
        var result = point
        let margin = settings.boundsMargin
        result.y = min(max(result.y, settings.altitude.lowerBound - margin), settings.altitude.upperBound + margin)
        var horizontal = SIMD3(result.x - viewer.x, 0, result.z - viewer.z)
        let distance = simd_length(horizontal)
        let farthest = settings.orbitRadius.upperBound + margin
        if distance > farthest {
            horizontal *= farthest / distance
            result.x = viewer.x + horizontal.x
            result.z = viewer.z + horizontal.z
        }
        let fromViewer = result - viewer
        let viewerDistance = simd_length(fromViewer)
        if viewerDistance < settings.personalSpace, viewerDistance > 1e-4 {
            result = viewer + fromViewer / viewerDistance * settings.personalSpace
        }
        return result
    }

    // MARK: - Manoeuvres

    private func begin(_ next: Maneuver, viewer: SIMD3<Float>) {
        maneuver = next
        elapsed = 0
        maneuverProgress = 0
        maneuverOrigin = positions[0]
        var forward = velocity
        forward.y = 0
        maneuverForward = simd_length(forward) > 1e-4 ? simd_normalize(forward) : SIMD3(0, 0, -1)
        let offset = positions[0] - viewer
        orbitAngle = atan2(offset.z, offset.x)
        if next == .cruise && Float.random(in: 0...1, using: &random) < 0.3 { orbitDirection *= -1 }

        switch next {
        case .takeoff, .cruise, .hover:
            beginInRoom(next, viewer: viewer)
        case .orbit:
            if let orbit { pathAngle = orbit.angle(closestTo: positions[0]) }
        case .approach:
            // In front of the player, on the line between them and the dragon (where they look when they tap it).
            let toDragon = SIMD3(offset.x, 0, offset.z)
            let direction = simd_length(toDragon) > 1e-4 ? simd_normalize(toDragon) : SIMD3(0, 0, -1)
            approachSpot = viewer + direction * settings.approachDistance
            approachSpot.y = viewer.y - 0.05
        case .land:
            beginLanding()
        case .depart:
            // Away from the player, beyond where it is.
            departDirection = simd_length(SIMD3(offset.x, 0, offset.z)) > 1e-4
                ? simd_normalize(SIMD3(offset.x, 0, offset.z)) : SIMD3(0, 0, -1)
        default:
            break
        }
    }

    /// Take-off, cruise and hover start relative to the player: away from them, in front of them.
    private func beginInRoom(_ next: Maneuver, viewer: SIMD3<Float>) {
        let away = SIMD3(positions[0].x - viewer.x, 0, positions[0].z - viewer.z)
        switch next {
        case .takeoff:
            // Climbs away from the player, never towards them.
            if simd_length(away) > 0.05 { maneuverForward = simd_normalize(away) }
        case .cruise:
            // In front of the player: the sweep starts where the dragon is, in the direction it is turning.
            arcCenter = atan2(viewerForward.z, viewerForward.x)
            if let arc = settings.frontArc, arc > 0 {
                let relative = atan2(sin(orbitAngle - arcCenter), cos(orbitAngle - arcCenter))
                let start = asin(max(-1, min(1, relative / arc)))
                arcPhase = orbitDirection > 0 ? start : .pi - start
            }
        default:
            hoverSpot = hoverTarget(viewer: viewer)
        }
    }

    /// "A life of its own": picks the next manoeuvre at random, weighted, never two dives or roars in a row.
    private func nextManeuver() -> Maneuver {
        let options: [(Maneuver, Float)] = switch maneuver {
        case .takeoff: [(.cruise, 1)]
        case .cruise: [(.swoop, 0.35), (.hover, 0.3), (.loop, 0.2), (.cruise, 0.15)]
        case .swoop, .hover, .loop, .approach, .land, .depart: [(.cruise, 1)]
        case .orbit: [(.orbit, 1)]
        }
        var roll = Float.random(in: 0..<options.reduce(0) { $0 + $1.1 }, using: &random)
        for (option, weight) in options {
            roll -= weight
            if roll < 0 { return option }
        }
        return .cruise
    }

    /// Point the head flies to, depending on the manoeuvre.
    private func target(viewer: SIMD3<Float>) -> SIMD3<Float> {
        let progress = maneuverProgress
        let midRadius = (settings.orbitRadius.lowerBound + settings.orbitRadius.upperBound) / 2
        let midAltitude = (settings.altitude.lowerBound + settings.altitude.upperBound) / 2

        switch maneuver {
        case .takeoff:
            // Climbs almost vertically, then moves away a little.
            return maneuverOrigin + SIMD3(0, 0.9, 0) + maneuverForward * (0.6 * progress)
        case .cruise:
            // Circle around the player (or a sweep in front of them), with breathing radius and altitude.
            let breathing = min(0.3, (settings.orbitRadius.upperBound - settings.orbitRadius.lowerBound) / 2)
            let rising = min(0.45, (settings.altitude.upperBound - settings.altitude.lowerBound) / 2)
            let radius = midRadius + breathing * sin(elapsed * 0.7)
            let height = midAltitude + rising * sin(elapsed * 0.9)
            if let arc = settings.frontArc, arc > 0 {
                // Side to side in front of the player, never behind them: at most `speed` along the arc.
                let rate = settings.speed / (midRadius * arc)
                let angle = arcCenter + arc * sin(arcPhase + elapsed * rate)
                return SIMD3(viewer.x + radius * cos(angle), height, viewer.z + radius * sin(angle))
            }
            orbitAngle += orbitDirection * 0.012
            return SIMD3(viewer.x + radius * cos(orbitAngle + orbitDirection * 0.6), height,
                         viewer.z + radius * sin(orbitAngle + orbitDirection * 0.6))
        case .swoop:
            // First dives beside the player, then climbs on the other side.
            let toViewer = SIMD3(viewer.x - maneuverOrigin.x, 0, viewer.z - maneuverOrigin.z)
            let across = simd_length(toViewer) > 1e-4 ? simd_normalize(toViewer) : maneuverForward
            let side = SIMD3(-across.z, 0, across.x) * orbitDirection
            let low = SIMD3(viewer.x, settings.altitude.lowerBound, viewer.z) + side * (settings.personalSpace + 0.5)
            let far = low + across * 1.4 + SIMD3(0, 0.8, 0)
            return progress < 0.5 ? low : far
        case .hover:
            // Straight in front of the player's eyes, at their height, swaying gently from side to side.
            let side = SIMD3(-viewerForward.z, 0, viewerForward.x)
            return hoverSpot + side * (0.1 * sin(elapsed * 2)) + SIMD3(0, 0.06 * sin(elapsed * 3), 0)
        case .loop:
            // Vertical circle in the plane (forward, up).
            let angle = progress * 2 * .pi
            let radius: Float = 0.45
            let center = maneuverOrigin + maneuverForward * 0.6 + SIMD3(0, radius, 0)
            return center + maneuverForward * (radius * sin(angle) + 0.5) - SIMD3(0, radius * cos(angle), 0)
        case .approach:
            // Arrives and hovers, swaying gently.
            return approachSpot + SIMD3(0.06 * sin(elapsed * 1.7), 0.04 * sin(elapsed * 2.3), 0)
        case .depart:
            // A target running ahead and gently up: away from the player, fading before the ceiling.
            return positions[0] + (departDirection + SIMD3(0, 0.35, 0)) * 2
        case .orbit, .land:
            // They follow a path, they do not steer.
            return positions[0]
        }
    }

    private func steer(toward target: SIMD3<Float>, viewer: SIMD3<Float>, dt: Float) {
        let head = positions[0]
        var desired = target - head
        let distance = simd_length(desired)
        let speed: Float = switch maneuver {
        // Hovering, it slows down almost to a stop.
        case .hover, .approach: min(settings.speed, distance * 1.5) + 0.08
        // Leaving, it speeds up.
        case .depart: settings.speed * (1 + 2.5 * maneuverProgress)
        default: settings.speed
        }
        desired = distance > 1e-4 ? desired / distance * speed : .zero

        // Personal space: pushed away from the player's head.
        let fromViewer = head - viewer
        let viewerDistance = simd_length(fromViewer)
        if viewerDistance < settings.personalSpace + 0.2, viewerDistance > 1e-4 {
            desired += fromViewer / viewerDistance * settings.speed * 2
        }
        if maneuver.staysInRoom {
            // Stays between the floor and the ceiling.
            if head.y < settings.altitude.lowerBound - 0.1 { desired.y += settings.speed }
            if head.y > settings.altitude.upperBound + 0.2 { desired.y -= settings.speed }
            // Does not go too far (walls of the room).
            let horizontal = SIMD3(fromViewer.x, 0, fromViewer.z)
            if simd_length(horizontal) > settings.orbitRadius.upperBound + 0.4 {
                desired -= simd_normalize(horizontal) * settings.speed
            }
        }

        velocity += (desired - velocity) * min(1, dt * settings.steering)
    }
}

// MARK: - Paths (tree, landing)

extension DragonFlight {
    private func advanceOnOrbit(dt: Float) -> SIMD3<Float> {
        guard let orbit else { return positions[0] }
        pathAngle += orbit.speed / orbit.radius * dt
        // The curve closes every two turns: the angle stays small (Float precision).
        if pathAngle > 4 * .pi { pathAngle -= 4 * .pi }
        return orbit.point(at: pathAngle)
    }

    /// Smooth curve from the head (in the direction it flies) to the tip of the knot's tail,
    /// arriving already lined up with the knot; then the knot itself, from tail to head.
    private func beginLanding() {
        landingPath = []
        landingTraveled = 0
        landingSegment = 0
        landingSegmentStart = 0
        guard landingKnot.count > 1 else {
            landingLength = 0
            return
        }
        let start = positions[0]
        let tail = landingKnot[landingKnot.count - 1]
        let along = simd_normalize(landingKnot[landingKnot.count - 2] - tail)
        let speed = simd_length(velocity)
        let forward = speed > 1e-4 ? velocity / speed : along
        let handle = max(0.15, simd_distance(start, tail) * 0.4)
        let control1 = start + forward * handle
        let control2 = tail - along * handle
        let samples = 24
        for step in 0...samples {
            // Cubic Bézier.
            let along = Float(step) / Float(samples)
            let rest = 1 - along
            landingPath.append(rest * rest * rest * start + 3 * rest * rest * along * control1
                               + 3 * rest * along * along * control2 + along * along * along * tail)
        }
        landingPath += landingKnot.reversed().dropFirst()
        landingLength = zip(landingPath, landingPath.dropFirst()).reduce(0) { $0 + simd_distance($1.0, $1.1) }
    }

    private var landingProgress: Float {
        landingLength > 0 ? min(landingTraveled / landingLength, 1) : 1
    }

    private func advanceOnLandingPath(dt: Float) -> SIMD3<Float> {
        guard landingPath.count > 1 else { return positions[0] }
        landingTraveled = min(landingTraveled + settings.landingSpeed * dt, landingLength)
        // Advances segment by segment (the cursor never goes back).
        while landingSegment < landingPath.count - 2 {
            let length = simd_distance(landingPath[landingSegment], landingPath[landingSegment + 1])
            if landingSegmentStart + length >= landingTraveled { break }
            landingSegmentStart += length
            landingSegment += 1
        }
        let from = landingPath[landingSegment]
        let to = landingPath[landingSegment + 1]
        let length = simd_distance(from, to)
        let fraction = length > 1e-6 ? min((landingTraveled - landingSegmentStart) / length, 1) : 1
        return simd_mix(from, to, SIMD3(repeating: fraction))
    }
}

extension DragonFlight {
    // MARK: - Body along the trail

    private func bodyAlongTrail(head: SIMD3<Float>) -> [SIMD3<Float>] {
        var result = [head]
        result.reserveCapacity(positions.count)
        var index = trail.count - 1
        var cursor = head
        var needed = segmentLength
        while result.count < positions.count {
            guard index > 0 else {
                // Trail used up: extend in the direction of the last segment.
                let last = result.count > 1 ? result[result.count - 1] - result[result.count - 2] : SIMD3(0, 0, segmentLength)
                result.append(result[result.count - 1] + simd_normalize(last) * segmentLength)
                continue
            }
            let previous = trail[index - 1]
            let step = simd_distance(cursor, previous)
            if step >= needed {
                cursor += (previous - cursor) * (needed / step)
                result.append(cursor)
                needed = segmentLength
            } else {
                needed -= step
                cursor = previous
                index -= 1
            }
        }
        return result
    }

    /// Keeps only the trail the body needs (plus a margin).
    private func trimTrail() {
        let bodyLength = segmentLength * Float(positions.count + 4)
        var length: Float = 0
        var index = trail.count - 1
        while index > 0 && length < bodyLength {
            length += simd_distance(trail[index], trail[index - 1])
            index -= 1
        }
        if index > 0 { trail.removeFirst(index) }
    }
}
