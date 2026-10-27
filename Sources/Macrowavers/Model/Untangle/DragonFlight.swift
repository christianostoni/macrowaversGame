import Foundation
import simd

/// The flying dragon: captive around the tree, stopping for the elixir, coming to the player and settling into
/// the knot.
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
    private(set) var maneuver = Maneuver.orbit
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
    /// Manoeuvres still to run (script); a manoeuvre left without a next one starts over.
    private var plan: [Maneuver] = []
    /// Angle of the head on `orbit`.
    private var pathAngle: Float = 0
    private var approachSpot = SIMD3<Float>.zero
    /// Path of the head while it settles, and how much of it is done.
    private var landingPath: [SIMD3<Float>] = []
    private var landingLength: Float = 0
    private var landingTraveled: Float = 0
    private var landingSegment = 0
    private var landingSegmentStart: Float = 0

    /// `start`: current body positions (index 0 = head) in scene space.
    /// `plan`: manoeuvres to run in order (the first starts at once).
    /// `viewer`: the player's eyes, when known.
    init(start: [SIMD3<Float>], segmentLength: Float, settings: Settings = Settings(), plan: [Maneuver],
         orbit: OrbitPath? = nil, viewer: SIMD3<Float>? = nil) {
        self.settings = settings
        self.segmentLength = segmentLength
        self.orbit = orbit
        positions = start
        // The initial trail is the body itself, from tail to head: as the head moves on the body "unrolls".
        trail = start.reversed()
        velocity = simd_normalize(start[0] - start[1]) * 0.3
        perform(plan, viewer: viewer ?? start[0])
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

    func update(deltaTime: Float, viewer: SIMD3<Float>) {
        guard !isFinished else { return }
        let dt = min(deltaTime, 1.0 / 30.0)
        guard dt > 0 else { return }
        elapsed += dt
        maneuverProgress = maneuver == .land ? landingProgress : min(elapsed / maneuver.duration, 1)
        if maneuverProgress >= 1 {
            if maneuver.isFinal && plan.isEmpty {
                isFinished = true
                return
            }
            begin(plan.isEmpty ? maneuver : plan.removeFirst(), viewer: viewer)
        }

        let head: SIMD3<Float>
        switch maneuver {
        case .orbit, .hold:
            // Fixed path: the velocity is whatever results (the rig and the next manoeuvre need it).
            head = advanceOnOrbit(dt: dt)
            velocity = (head - positions[0]) / dt
        case .land:
            head = advanceOnLandingPath(dt: dt)
            velocity = (head - positions[0]) / dt
        case .approach:
            steer(toward: approachTarget, viewer: viewer, dt: dt)
            head = positions[0] + velocity * dt
        case .cruise:
            // Drawn on the ride only: never flown here.
            head = positions[0]
        }

        if simd_distance(head, trail.last!) > segmentLength * 0.1 { trail.append(head) }
        positions = bodyAlongTrail(head: head)
        trimTrail()
    }

    // MARK: - Manoeuvres

    private func begin(_ next: Maneuver, viewer: SIMD3<Float>) {
        maneuver = next
        elapsed = 0
        maneuverProgress = 0
        let offset = positions[0] - viewer

        switch next {
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
        case .hold, .cruise:
            break
        }
    }

    /// Arriving in front of the player, it sways gently.
    private var approachTarget: SIMD3<Float> {
        approachSpot + SIMD3(0.06 * sin(elapsed * 1.7), 0.04 * sin(elapsed * 2.3), 0)
    }

    /// Steers the head towards `target`, slowing down almost to a stop as it gets there, and keeps it out of the
    /// player's personal space.
    private func steer(toward target: SIMD3<Float>, viewer: SIMD3<Float>, dt: Float) {
        let head = positions[0]
        var desired = target - head
        let distance = simd_length(desired)
        let speed = min(settings.speed, distance * 1.5) + 0.08
        desired = distance > 1e-4 ? desired / distance * speed : .zero

        // Personal space: pushed away from the player's head.
        let fromViewer = head - viewer
        let viewerDistance = simd_length(fromViewer)
        if viewerDistance < settings.personalSpace + 0.2, viewerDistance > 1e-4 {
            desired += fromViewer / viewerDistance * settings.speed * 2
        }

        velocity += (desired - velocity) * min(1, dt * settings.steering)
    }
}

// MARK: - Paths (tree, landing)

extension DragonFlight {
    /// How quickly a `.hold` slows the dragon down on its path (1/s): its speed is `e^(−holdBraking · t)` of the
    /// orbit's, nearly still after a second.
    static let holdBraking: Float = 2.5

    private func advanceOnOrbit(dt: Float) -> SIMD3<Float> {
        guard let orbit else { return positions[0] }
        // Holding, it brakes along the same path: the body stays on it and never crumples.
        let brake = maneuver == .hold ? exp(-elapsed * Self.holdBraking) : 1
        pathAngle += orbit.speed * brake / orbit.radius * dt
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
