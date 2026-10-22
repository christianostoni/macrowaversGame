import simd

/// Parameters of the dragon's body simulation.
/// All sizes are in metres (RealityKit units).
struct TangleConfig {
    /// Number of nodes (vertebrae) of the body: the control points of the spline the rig draws. More nodes =
    /// rounder curves in the knot and in flight (the rigged model samples the spline, any bone count works).
    var nodeCount = 64
    /// Rest distance between two consecutive nodes: the body stays ~2.35 m long.
    var segmentLength: Float = 2.35 / 63
    /// Body radius used for self-collisions; the rigs draw the body this thick.
    var radius: Float = 0.04
    /// Solver iterations per sub-step: the more, the "stiffer" the body.
    var solverIterations = 10
    /// Sub-steps per frame: they keep a segment from passing through another.
    var substeps = 4
    /// 1 = no friction, 0 = stops at once.
    var damping: Float = 0.9
    /// Friction between parts of the body that touch (0...1).
    var selfFriction: Float = 0.3
    /// Friction with the ground: without it the tangle tends to slide loose by itself.
    var groundFriction: Float = 0.6
    /// The head stays where it is unless the player holds it (the dragon "holds" its head on the ground): grabbed,
    /// it follows the hand like any node, and let go it stays where it was put. Without a fixed point, pulling the
    /// tail drags the whole body away and the knot comes undone by itself.
    var anchorHead = true
    /// Share of its height a node loses per sub-step towards the plane y = 0 (the dragon "lies" on the ground). The
    /// pull builds up no speed (see `integrate`); 0.04 with that made the resting knot loosen by itself.
    var flattenStrength: Float = 0.02
    /// Bending stiffness (0...1): prevents elbows that are too sharp.
    var bendStiffness: Float = 0.25
    /// Height at which the dragon lifts its tail when it thrashes: it passes OVER its own body
    /// (clear of a body lying on the plane: more than three radii).
    var grabLift: Float = 0.12
    /// Stretch beyond which grabbed nodes stop following the hands (1.05 = +5%).
    var maxTension: Float = 1.04
    /// Maximum movement of a grabbed node per sub-step (anti-tunnelling).
    var maxGrabSpeed: Float = 0.015
    /// Time constant (s) of the filter between the hand and the grabbed node: hand-tracking noise and sudden
    /// pinches do not shake the body.
    var grabSmoothing: Float = 0.06
    /// Tension band before `maxTension` where a grabbed node slows down gradually instead of stopping dead
    /// (a hard stop made the node flicker between following the hand and giving way).
    var tensionSoftness: Float = 0.02
    /// How far ahead of its node a hand's target may be (m). The hand (its collider) can get far from a node the
    /// body holds back; without a leash, the node rushed after it like a rubber band as soon as the body gave way.
    var grabLeash: Float = 0.08
    /// Segments on each side of a grabbed node whose mean stretch holds that grab back (see `grabTensions`).
    var tensionReach = 8
    /// Segments this close along the body never count as crossing each other: a small kink or a loop of a few
    /// segments is not a knot (it showed phantom markers and blocked the win).
    var crossingSkip = 8

    /// Nodes this close along the body never collide with each other: they touch because they are neighbours.
    var collisionSkip: Int {
        max(3, Int((2 * radius / segmentLength).rounded(.up)) + 1)
    }
}

/// The dragon's body simulated as a rope of nodes (Position Based Dynamics / Verlet).
/// No dependency on RealityKit: it can be tested on its own and reused with any renderer.
final class TangleSimulation {
    let config: TangleConfig
    private(set) var positions: [SIMD3<Float>]
    private var previous: [SIMD3<Float>]
    /// The body at the start of the last tick: what is drawn goes from here to `positions`.
    private var tickStart: [SIMD3<Float>]
    /// Grabbed nodes (even more than one: one per hand) and where to bring them.
    private var grabTargets: [Int: SIMD3<Float>] = [:]
    /// Where each grabbed node is heading: `grabTargets` filtered (see `TangleConfig.grabSmoothing`).
    private var smoothedTargets: [Int: SIMD3<Float>] = [:]

    init(config: TangleConfig = TangleConfig(), positions: [SIMD3<Float>]) {
        precondition(positions.count == config.nodeCount, "positions.count must equal config.nodeCount")
        self.config = config
        self.positions = positions
        self.previous = positions
        self.tickStart = positions
    }

    // MARK: - Interaction

    var grabbedIndices: Dictionary<Int, SIMD3<Float>>.Keys { grabTargets.keys }
    var hasGrabs: Bool { !grabTargets.isEmpty }

    func isGrabbed(_ index: Int) -> Bool { grabTargets[index] != nil }

    /// Returns `false` if there is no such node. The head can be grabbed too: held, it follows the hand.
    /// `filtered`: the target goes through `TangleConfig.grabSmoothing` (a hand); the dragon's own moves are exact.
    @discardableResult
    func grab(_ index: Int, filtered: Bool = true) -> Bool {
        guard positions.indices.contains(index) else { return false }
        grabTargets[index] = positions[index]
        if filtered { smoothedTargets[index] = positions[index] }
        return true
    }

    /// `point` in 3D: the height decides whether the part passes over or under the others.
    /// It never goes below the plane. A hand's target stays within `grabLeash` of its node.
    func drag(_ index: Int, to point: SIMD3<Float>) {
        guard grabTargets[index] != nil else { return }
        var target = SIMD3(point.x, max(point.y, config.radius), point.z)
        if smoothedTargets[index] != nil {
            let ahead = target - positions[index]
            let distance = simd_length(ahead)
            if distance > config.grabLeash { target = positions[index] + ahead / distance * config.grabLeash }
        }
        grabTargets[index] = target
    }

    func release(_ index: Int) {
        grabTargets[index] = nil
        smoothedTargets[index] = nil
    }

    func releaseAll() {
        grabTargets.removeAll()
        smoothedTargets.removeAll()
    }

    /// Rotates the whole body rigidly around a vertical axis (the dragon turns around).
    /// A rigid rotation does not change the crossings: a spectacular move, but "fair" for the puzzle.
    func rotateBody(by angle: Float, around center: SIMD3<Float>) {
        let cosine = cos(angle), sine = sin(angle)
        func rotate(_ point: SIMD3<Float>) -> SIMD3<Float> {
            let offset = point - center
            return SIMD3(center.x + offset.x * cosine - offset.z * sine, point.y, center.z + offset.x * sine + offset.z * cosine)
        }
        positions = positions.map(rotate)
        previous = previous.map(rotate)
        tickStart = tickStart.map(rotate)
        grabTargets = grabTargets.mapValues(rotate)
        smoothedTargets = smoothedTargets.mapValues(rotate)
    }

    var centroid: SIMD3<Float> {
        positions.reduce(SIMD3<Float>.zero, +) / Float(positions.count)
    }

    // MARK: - Simulation

    /// Advances the simulation at a fixed step (60 Hz), independent of the frame rate.
    func step(deltaTime: Float) {
        accumulator = min(accumulator + deltaTime, 0.1)
        while accumulator >= Self.tick {
            accumulator -= Self.tick
            tickStart = positions
            for _ in 0..<config.substeps {
                integrate()
                moveGrabbedNodes()
                findContactCandidates()
                for _ in 0..<config.solverIterations {
                    solveDistances()
                    solveBending()
                    solveSelfCollisions()
                }
                applyFriction()
                measureTension()
            }
        }
    }

    /// The body to draw: between the last two ticks, as far as the time not yet simulated. The headset draws at
    /// 90 Hz: drawn as is, the 60 Hz body stood still one frame in three. It lags at most one tick behind.
    var interpolatedPositions: [SIMD3<Float>] {
        let amount = SIMD3(repeating: accumulator / Self.tick)
        return zip(tickStart, positions).map { simd_mix($0, $1, amount) }
    }

    private static let tick: Float = 1.0 / 60.0
    private var accumulator: Float = 0
    /// Pairs of nodes close enough to touch during this sub-step (see `findContactCandidates`).
    private var contactCandidates: [(Int, Int)] = []

    private func integrate() {
        for i in positions.indices where inverseMass(i) > 0 {
            var velocity = (positions[i] - previous[i]) * config.damping
            if positions[i].y < config.radius * 1.5 {
                velocity.x *= config.groundFriction
                velocity.z *= config.groundFriction
            }
            previous[i] = positions[i]
            positions[i] += velocity
            // Soft pull towards the plane: the body "settles" but the collisions keep over/under. `previous` moves
            // with it, so the pull never builds up speed (a stone let go 20 cm up used to slam down at ~7 m/s).
            let settle = positions[i].y * config.flattenStrength
            positions[i].y -= settle
            previous[i].y -= settle
        }
        // The anchored head let go in the air settles back onto the plane: it has no mass, nothing else moves it,
        // and left up there it would hold the neck up.
        if config.anchorHead, grabTargets[0] == nil, positions[0].y > config.radius {
            positions[0].y += (config.radius - positions[0].y) * Self.headSettle
        }
    }

    /// Share of the anchored head's height above the plane it loses per sub-step (~0.2 s to settle).
    private static let headSettle: Float = 0.02

    /// How taut the body is where it is held (1 = at rest, or nothing held): the tauter of `grabTensions`. When the
    /// body is taut the constraints cannot all be satisfied and one part would end up passing through another: in
    /// that case the grabbed node stops advancing. Also useful as feedback (the dragon "suffers" when pulled too hard).
    private(set) var tension: Float = 1
    /// How taut the body is around each grabbed node (1 = at rest): the mean stretch of the `tensionReach` segments
    /// on its tauter side. Each hand is held back only by the stretch of the body it pulls. The single most stretched
    /// segment of the whole body used to hold back every grab at once: one hand pulling the body taut froze the
    /// other, and a 4 % limit on one segment (1.5 mm) stopped a node that a fast hand had barely moved.
    private(set) var grabTensions: [Int: Float] = [:]
    /// Each side of each grabbed node: its stretch, and the direction that would stretch it further (away from the
    /// node two segments along that side: the local direction of the body).
    private var grabSides: [Int: [(tension: Float, away: SIMD3<Float>)]] = [:]

    private func measureTension() {
        var sides: [Int: [(tension: Float, away: SIMD3<Float>)]] = [:]
        for node in grabTargets.keys {
            let windows = [(max(0, node - config.tensionReach), node, max(0, node - config.tensionReach)),
                           (node, min(positions.count - 1, node + config.tensionReach),
                            min(positions.count - 1, node + config.tensionReach))]
            sides[node] = windows.compactMap { low, high, far in
                guard high > low else { return nil }
                var length: Float = 0
                for k in low..<high { length += simd_distance(positions[k], positions[k + 1]) }
                let along = max(0, min(positions.count - 1, far < node ? node - 2 : node + 2))
                let away = positions[node] - positions[along]
                let distance = simd_length(away)
                return (length / (Float(high - low) * config.segmentLength), distance > 1e-6 ? away / distance : .zero)
            }
        }
        grabSides = sides
        grabTensions = sides.mapValues { $0.map(\.tension).max() ?? 1 }
        tension = grabTensions.values.max() ?? 1
    }

    private func moveGrabbedNodes() {
        let substep = Self.tick / Float(config.substeps)
        let follow = config.grabSmoothing > 0 ? 1 - exp(-substep / config.grabSmoothing) : 1
        let softness = max(config.tensionSoftness, 1e-4)
        for (node, target) in grabTargets {
            // Beyond the limit (e.g. two hands pulling in opposite directions) the node gives way towards its
            // neighbours, as much as the body is overstretched, instead of tearing it.
            let tension = grabTensions[node] ?? 1
            let giveWay = max(0, min(1, (tension - config.maxTension) / softness)) * 0.05
            previous[node] = positions[node]
            var smoothed = target
            if let previousTarget = smoothedTargets[node] {
                smoothed = simd_mix(previousTarget, target, SIMD3(repeating: follow))
                smoothedTargets[node] = smoothed
            }
            var delta = smoothed - positions[node]
            // The part of the move that stretches a taut side stops (1 below the soft band, 0 at `maxTension`);
            // sideways the node still follows its hand, slowly (`tautSideways`), and back towards that side freely.
            // So when one hand pulls the body taut the other can still lift or move its part, the pulling one gives
            // way, and a shaky hand on a taut body does not shake it.
            for side in grabSides[node] ?? [] {
                let freedom = max(0, min(1, (config.maxTension - side.tension) / softness))
                guard freedom < 1 else { continue }
                let stretching = simd_dot(delta, side.away)
                if stretching > 0 { delta -= side.away * stretching * (1 - freedom) }
                let lengthwise = side.away * simd_dot(delta, side.away)
                delta = lengthwise + (delta - lengthwise) * max(freedom, Self.tautSideways)
            }
            let distance = simd_length(delta)
            let reach = config.maxGrabSpeed
            positions[node] += distance > reach ? delta / max(distance, 1e-6) * reach : delta
            if giveWay > 0 {
                let before = positions[max(node - 1, 0)]
                let after = positions[min(node + 1, positions.count - 1)]
                positions[node] += ((before + after) / 2 - positions[node]) * giveWay
            }
        }
    }

    /// Share of a sideways move a node held on a taut side still makes per sub-step.
    private static let tautSideways: Float = 0.15

    /// Inverse mass: grabbed nodes, and the anchored head where it was left, have infinite mass (the constraints do
    /// not move them).
    private func inverseMass(_ i: Int) -> Float {
        if grabTargets[i] != nil || (config.anchorHead && i == 0) { return 0 }
        return 1
    }

    private func satisfy(_ i: Int, _ j: Int, restLength: Float, stiffness: Float = 1, onlyIfShorter: Bool = false) {
        let wi = inverseMass(i), wj = inverseMass(j)
        guard wi + wj > 0 else { return }
        let delta = positions[j] - positions[i]
        let distance = simd_length(delta)
        guard distance > 1e-6 else { return }
        if onlyIfShorter && distance >= restLength { return }
        let correction = delta * ((distance - restLength) / (distance * (wi + wj))) * stiffness
        positions[i] += correction * wi
        positions[j] -= correction * wj
    }

    private func solveDistances() {
        for i in 0..<(positions.count - 1) {
            satisfy(i, i + 1, restLength: config.segmentLength)
        }
    }

    private func solveBending() {
        // Keeps nodes i and i+2 at a minimum distance: maximum bend angle ~110°.
        let minimum = config.segmentLength * 1.15
        for i in 0..<(positions.count - 2) {
            satisfy(i, i + 2, restLength: minimum, stiffness: config.bendStiffness, onlyIfShorter: true)
        }
    }

    /// Broad phase, once per sub-step: the solver iterations move nodes by millimetres, so only the pairs found
    /// here (within a margin of contact) can collide. Keeps the cost low with many nodes, even in debug builds.
    private func findContactCandidates() {
        contactCandidates.removeAll(keepingCapacity: true)
        let reach = config.radius * 3
        let count = positions.count
        let skip = config.collisionSkip
        for i in 0..<count {
            for j in (i + skip)..<max(i + skip, count)
            where simd_length_squared(positions[j] - positions[i]) < reach * reach {
                contactCandidates.append((i, j))
            }
        }
    }

    private func solveSelfCollisions() {
        let minDistance = config.radius * 2
        for (i, j) in contactCandidates {
            let delta = positions[j] - positions[i]
            let distanceSquared = simd_length_squared(delta)
            guard distanceSquared < minDistance * minDistance else { continue }
            if inverseMass(i) == 0 && inverseMass(j) == 0 {
                // Two held parts (or a held part and the anchored head): the constraint would move neither, and
                // they passed straight through each other. Each gives way by half.
                let distance = sqrt(distanceSquared)
                let normal = distance > 1e-6 ? delta / distance : SIMD3(0, 1, 0)
                let push = (minDistance - distance) * 0.5
                positions[i] -= normal * push
                positions[j] += normal * push
            } else {
                satisfy(i, j, restLength: minDistance, onlyIfShorter: true)
            }
        }
    }

    /// Friction between two parts of the body in contact, once per sub-step after the constraints: without it a
    /// tight knot slips away by itself when an end is pulled, and the puzzle gets solved "by chance". Coulomb-like:
    /// a contact holds a slip back as much as it is pressed (`selfFriction` × its depth) and no more, so a contact
    /// barely touching holds nothing (a fixed minimum made a taut body stick and slip). Applied in every solver
    /// iteration, without a limit, it took away ~97 % of the sliding per sub-step: the knot stuck to the hand that
    /// pulled it, which juddered.
    private func applyFriction() {
        guard config.selfFriction > 0 else { return }
        let minDistance = config.radius * 2
        for (i, j) in contactCandidates {
            let delta = positions[j] - positions[i]
            let distance = simd_length(delta)
            guard distance < minDistance * 1.02, distance > 1e-6 else { continue }
            let wi = inverseMass(i), wj = inverseMass(j)
            guard wi + wj > 0 else { continue }
            let normal = delta / distance
            let relative = (positions[i] - previous[i]) - (positions[j] - previous[j])
            let tangential = relative - normal * simd_dot(relative, normal)
            let slip = simd_length(tangential)
            guard slip > 1e-7 else { continue }
            let limit = config.selfFriction * max(minDistance - distance, 0) * 4
            let correction = tangential / slip * (min(slip, limit) / (wi + wj))
            positions[i] -= correction * wi
            positions[j] += correction * wj
        }
    }

    // MARK: - Tangle

    /// Crossings of the body seen from above (projection on the XZ plane).
    /// The dragon is free when there are no crossings left.
    func crossings() -> [Crossing] {
        crossings(of: positions)
    }

    /// The crossings of the body as it is drawn (`interpolatedPositions`): the markers sit on it, without lagging.
    func drawnCrossings() -> [Crossing] {
        crossings(of: interpolatedPositions)
    }

    private func crossings(of positions: [SIMD3<Float>]) -> [Crossing] {
        var result: [Crossing] = []
        let count = positions.count
        let skip = max(config.crossingSkip, 2)
        for i in 0..<(count - 1) {
            for j in (i + skip)..<max(i + skip, count - 1) {
                let a0 = positions[i], a1 = positions[i + 1]
                let b0 = positions[j], b1 = positions[j + 1]
                guard let (alongA, alongB) = segmentIntersection(
                    SIMD2(a0.x, a0.z), SIMD2(a1.x, a1.z),
                    SIMD2(b0.x, b0.z), SIMD2(b1.x, b1.z)
                ) else { continue }
                let pointA = a0 + (a1 - a0) * alongA
                let pointB = b0 + (b1 - b0) * alongB
                result.append(Crossing(segmentA: i, segmentB: j, aIsOver: pointA.y > pointB.y,
                                       position: (pointA + pointB) / 2))
            }
        }
        return result
    }

    private func segmentIntersection(_ startA: SIMD2<Float>, _ endA: SIMD2<Float>,
                                     _ startB: SIMD2<Float>, _ endB: SIMD2<Float>) -> (Float, Float)? {
        let directionA = endA - startA, directionB = endB - startB
        let denominator = directionA.x * directionB.y - directionA.y * directionB.x
        guard abs(denominator) > 1e-9 else { return nil }
        let offset = startB - startA
        let alongA = (offset.x * directionB.y - offset.y * directionB.x) / denominator
        let alongB = (offset.x * directionA.y - offset.y * directionA.x) / denominator
        guard (0...1).contains(alongA), (0...1).contains(alongB) else { return nil }
        return (alongA, alongB)
    }
}

struct Crossing {
    /// Segment `segmentA` goes from node `segmentA` to node `segmentA + 1`.
    let segmentA: Int
    let segmentB: Int
    let aIsOver: Bool
    /// Point of the crossing (half-way in height between the two parts).
    let position: SIMD3<Float>
}
