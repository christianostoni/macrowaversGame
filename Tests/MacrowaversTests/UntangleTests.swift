import simd
import Testing
@testable import Macrowavers

struct TangleSimulationTests {
    @Test func initialShapesHaveExpectedCrossings() {
        let config = TangleConfig()
        let trefoil = TangleSimulation(config: config, positions: TangleShape.trefoil.positions(config: config))
        let figureEight = TangleSimulation(config: config, positions: TangleShape.figureEight.positions(config: config))

        #expect(trefoil.crossings().count == 3)
        #expect(figureEight.crossings().count == 4)
    }

    @Test func untouchedDragonStaysTangled() {
        let config = TangleConfig()
        let simulation = TangleSimulation(config: config, positions: TangleShape.trefoil.positions(config: config))
        for _ in 0..<300 { simulation.step(deltaTime: 1.0 / 60.0) }

        #expect(simulation.crossings().count == 3)
    }

    @Test func rigidTurnKeepsCrossingsAndShape() {
        let config = TangleConfig()
        let simulation = TangleSimulation(config: config, positions: TangleShape.figureEight.positions(config: config))
        let before = simulation.crossings().count
        let firstSegment = simd_distance(simulation.positions[0], simulation.positions[1])

        simulation.rotateBody(by: .pi * 0.7, around: simulation.centroid)

        #expect(simulation.crossings().count == before)
        #expect(abs(simd_distance(simulation.positions[0], simulation.positions[1]) - firstSegment) < 1e-5)
    }

    @Test func anchoredHeadCannotBeGrabbed() {
        let config = TangleConfig()
        let simulation = TangleSimulation(config: config, positions: TangleShape.trefoil.positions(config: config))

        #expect(!simulation.grab(0))
        #expect(simulation.grab(config.nodeCount - 1))
        #expect(simulation.isGrabbed(config.nodeCount - 1))
    }

    @Test func twoHandsCanHoldTwoNodes() {
        let config = TangleConfig()
        let simulation = TangleSimulation(config: config, positions: TangleShape.trefoil.positions(config: config))
        simulation.grab(20)
        simulation.grab(config.nodeCount - 1)
        let restingHeight = simulation.positions[20].y
        let lifted = simulation.positions[20] + SIMD3(0, 0.1, 0)
        for _ in 0..<120 {
            simulation.drag(20, to: lifted)
            simulation.step(deltaTime: 1.0 / 60.0)
        }

        // It rises as far as the tension limit allows, while the other hand holds the tail.
        #expect(simulation.positions[20].y > restingHeight + 0.01)
        #expect(simulation.isGrabbed(config.nodeCount - 1))
    }

    @Test func shakyHandDoesNotShakeTheBody() {
        let config = TangleConfig()
        let simulation = TangleSimulation(config: config, positions: TangleShape.trefoil.positions(config: config))
        let node = config.nodeCount - 1
        simulation.grab(node)
        let hand = simulation.positions[node] + SIMD3(0.06, 0.04, 0)
        var heights: [Float] = []
        for frame in 0..<120 {
            // Hand-tracking noise: ±1 cm every frame.
            let noise: Float = frame.isMultiple(of: 2) ? 0.01 : -0.01
            simulation.drag(node, to: hand + SIMD3(noise, noise, noise))
            simulation.step(deltaTime: 1.0 / 60.0)
            heights.append(simulation.positions[node].y)
        }

        let settled = heights.suffix(30)
        #expect(settled.max()! - settled.min()! < 0.005)
        #expect(abs(heights.last! - hand.y) < 0.01)
    }

    @Test func oneHandPullingTautDoesNotLockTheOtherHand() {
        let config = TangleConfig()
        let simulation = TangleSimulation(config: config, positions: TangleShape.trefoil.positions(config: config))
        let tail = config.nodeCount - 1
        let middle = config.nodeCount / 3
        simulation.grab(tail)
        simulation.grab(middle)
        // The right hand pulls the tail until the body is taut, the left hand just holds its node.
        let pulled = simulation.positions[tail] + SIMD3(0.8, 0.05, 0)
        let held = simulation.positions[middle]
        for _ in 0..<90 {
            simulation.drag(tail, to: pulled)
            simulation.drag(middle, to: held)
            simulation.step(deltaTime: 1.0 / 60.0)
        }
        #expect(simulation.tension > config.maxTension - config.tensionSoftness)

        // Now the left hand lifts its node: it must follow, even though the body is taut.
        let start = simulation.positions[middle]
        for _ in 0..<60 {
            simulation.drag(tail, to: pulled)
            simulation.drag(middle, to: start + SIMD3(0, 0.06, 0))
            simulation.step(deltaTime: 1.0 / 60.0)
        }

        #expect(simulation.positions[middle].y > start.y + 0.03)
        #expect(simulation.tension < config.maxTension + config.tensionSoftness * 2)
    }

    @Test func tautBodyGivesWayWithoutFlickering() {
        let config = TangleConfig()
        let simulation = TangleSimulation(config: config, positions: TangleShape.trefoil.positions(config: config))
        let first = config.nodeCount * 2 / 5
        let second = config.nodeCount - 1
        simulation.grab(first)
        simulation.grab(second)
        // The two hands pull far apart, one of them shaky: the body cannot follow both.
        let left = simulation.positions[first] + SIMD3(-0.6, 0.05, 0)
        let right = simulation.positions[second] + SIMD3(0.6, 0.05, 0)
        var jerk: Float = 0
        var frames: Float = 0
        var previousStep = SIMD3<Float>.zero
        var previous = simulation.positions[second]
        for frame in 0..<240 {
            let noise: Float = frame.isMultiple(of: 2) ? 0.008 : -0.008
            simulation.drag(first, to: left)
            simulation.drag(second, to: right + SIMD3(repeating: noise))
            simulation.step(deltaTime: 1.0 / 60.0)
            let step = simulation.positions[second] - previous
            previous = simulation.positions[second]
            // Once taut, the held node must not jerk back and forth (it used to: ~3 mm per frame, 39 mm shaky).
            if frame > 60 {
                jerk += simd_length(step - previousStep)
                frames += 1
            }
            previousStep = step
        }

        #expect(jerk / frames < 0.0003)
        #expect(simulation.tension < config.maxTension + config.tensionSoftness * 2)
    }
}

struct DragonBehaviorTests {
    @Test func fitStartsWithATurnAfterTheDelay() {
        let config = TangleConfig()
        let simulation = TangleSimulation(config: config, positions: TangleShape.trefoil.positions(config: config))
        let behavior = DragonBehavior()
        var elapsed: Float = 0
        while behavior.currentAction == nil && elapsed < 20 {
            behavior.update(deltaTime: 1.0 / 60.0, crossings: simulation.crossings().count,
                            userIsGrabbing: false, simulation: simulation)
            simulation.step(deltaTime: 1.0 / 60.0)
            elapsed += 1.0 / 60.0
        }

        guard case .turn = behavior.currentAction else {
            Issue.record("The first move should be a turn, got \(String(describing: behavior.currentAction))")
            return
        }
        #expect(abs(elapsed - DifficultySettings().firstWriggleDelay) < 0.1)
    }

    @Test func dragonWaitsWhileTheUserHoldsIt() {
        let config = TangleConfig()
        let simulation = TangleSimulation(config: config, positions: TangleShape.trefoil.positions(config: config))
        let behavior = DragonBehavior()
        for _ in 0..<(60 * 20) {
            behavior.update(deltaTime: 1.0 / 60.0, crossings: 3, userIsGrabbing: true, simulation: simulation)
        }

        #expect(!behavior.isWriggling)
        #expect(behavior.restlessness == 1)
    }
}

struct DragonFlightTests {
    @Test func flightRespectsThePlayersPersonalSpace() {
        let config = TangleConfig()
        let start = TangleShape.trefoil.positions(config: config).map { $0 + SIMD3<Float>(0, 0.75, -0.6) }
        let viewer = SIMD3<Float>(0, 1.15, 0)
        let flight = DragonFlight(start: start, segmentLength: config.segmentLength)
        var closest = Float.infinity
        for _ in 0..<(60 * 40) {
            flight.update(deltaTime: 1.0 / 60.0, viewer: viewer)
            #expect(flight.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
            closest = min(closest, simd_distance(flight.positions[0], viewer))
        }

        #expect(closest > flight.settings.personalSpace * 0.9)
        #expect(flight.positions.count == config.nodeCount)
    }

    @Test func captiveDragonCoilsAroundTheTreeWithoutCrossingItself() {
        let config = TangleConfig()
        let island = IslandPlacement.standard
        let orbit = OrbitPath.aroundTree.placed(at: island.position, scale: island.scale)
        let flight = DragonFlight.captive(on: orbit, nodeCount: config.nodeCount, segmentLength: config.segmentLength)
        var closestSelf = Float.infinity
        var previous = flight.positions
        var largestStep: Float = 0
        for _ in 0..<(60 * 20) {
            flight.update(deltaTime: 1.0 / 60.0, viewer: SIMD3(0, 1.15, 0))
            let positions = flight.positions
            for first in positions.indices {
                for second in (first + 4)..<max(first + 4, positions.count) {
                    closestSelf = min(closestSelf, simd_distance(positions[first], positions[second]))
                }
            }
            largestStep = max(largestStep, zip(previous, positions).map { simd_distance($0, $1) }.max() ?? 0)
            previous = positions
        }

        #expect(flight.maneuver == .orbit)
        #expect(closestSelf > 2 * config.radius)
        // No jumps: at 0.35 m/s a node moves less than 1 cm per frame.
        #expect(largestStep < 0.01)
    }

    @Test func landingLaysTheBodyOnTheKnot() {
        let config = TangleConfig()
        let orbit = OrbitPath.aroundTree.placed(at: IslandPlacement.standard.position, scale: IslandPlacement.standard.scale)
        let flight = DragonFlight.captive(on: orbit, nodeCount: config.nodeCount, segmentLength: config.segmentLength)
        let knot = TangleShape.trefoil.positions(config: config).map { $0 + SIMD3<Float>(0, 0.75, -0.6) }
        flight.landingKnot = knot
        flight.perform([.approach, .land], viewer: SIMD3(0, 1.15, 0))
        var elapsed: Float = 0
        while !flight.isFinished && elapsed < 30 {
            flight.update(deltaTime: 1.0 / 60.0, viewer: SIMD3(0, 1.15, 0))
            elapsed += 1.0 / 60.0
        }

        #expect(flight.isFinished)
        #expect(simd_distance(flight.positions[0], knot[0]) < 0.001)
        #expect(zip(flight.positions, knot).allSatisfy { simd_distance($0, $1) < 0.03 })
    }

    @Test func farewellEndsWithTheDragonGone() {
        let config = TangleConfig()
        let start = TangleShape.trefoil.positions(config: config).map { $0 + SIMD3<Float>(0, 0.75, -0.6) }
        let flight = DragonFlight(start: start, segmentLength: config.segmentLength,
                                  plan: [.takeoff, .cruise, .hover, .depart])
        var elapsed: Float = 0
        while !flight.isFinished && elapsed < 60 {
            flight.update(deltaTime: 1.0 / 60.0, viewer: SIMD3(0, 1.15, 0))
            elapsed += 1.0 / 60.0
        }

        #expect(flight.isFinished)
        #expect(flight.maneuver == .depart)
    }

    @Test(arguments: [SIMD3<Float>(0, 0, -1), simd_normalize(SIMD3<Float>(0.6, -0.3, -1))])
    func freeDragonStaysInFrontOfThePlayerAndHoversWhereTheyLook(forward: SIMD3<Float>) {
        let config = TangleConfig()
        let viewer = SIMD3<Float>(0, 1.15, 0)
        let settings = DragonFlight.Settings.farewell
        let flat = simd_normalize(SIMD3(forward.x, 0, forward.z))
        let start = TangleShape.trefoil.positions(config: config).map { $0 + SIMD3<Float>(0, 0.75, -0.6) }
        let flight = DragonFlight(start: start, segmentLength: config.segmentLength, settings: settings,
                                  plan: [.takeoff, .cruise, .hover, .depart], viewer: viewer, viewerForward: forward)
        var departStart: SIMD3<Float>?
        var hoverEnd: SIMD3<Float>?
        var elapsed: Float = 0
        while !flight.isFinished && elapsed < 60 {
            flight.update(deltaTime: 1.0 / 60.0, viewer: viewer, viewerForward: forward)
            elapsed += 1.0 / 60.0
            let head = flight.positions[0]
            let offset = SIMD3(head.x - viewer.x, 0, head.z - viewer.z)
            if flight.maneuver == .hover { hoverEnd = head }
            if flight.maneuver == .depart && departStart == nil { departStart = head }
            guard flight.maneuver == .cruise || flight.maneuver == .hover else { continue }
            // Within the flight volume and never behind or beside the player.
            #expect(simd_length(offset) < settings.orbitRadius.upperBound + settings.boundsMargin + 0.05)
            #expect(head.y < settings.altitude.upperBound + settings.boundsMargin + 0.05)
            #expect(simd_distance(head, viewer) > settings.personalSpace * 0.95)
            #expect(simd_dot(simd_normalize(offset), flat) > cos(settings.frontArc! + 0.35))
        }

        #expect(flight.isFinished)
        // It thanked the player straight in front of their eyes, at a comfortable distance.
        let spot = viewer + flat * settings.hoverDistance
        #expect(hoverEnd.map { simd_distance($0, spot) < 0.25 } == true)
        // It faded out within a couple of metres: before the room's walls or ceiling.
        #expect(departStart.map { simd_distance(flight.positions[0], $0) < settings.departFade.upperBound + 0.2 } == true)
        #expect(flight.positions.allSatisfy { $0.y < 2.6 })
    }
}

struct HandGrabsTests {
    @Test func eachHandHoldsItsOwnNode() {
        var grabs = HandGrabs()

        #expect(grabs.began(node: 10, hands: [.left]) == [.grab(10)])
        #expect(grabs.began(node: 40, hands: [.right]) == [.grab(40)])
        #expect(grabs.node(heldBy: .left) == 10)
        #expect(grabs.node(heldBy: .right) == 40)
        // The left hand lets go: the right one keeps its node.
        #expect(grabs.released(node: 10) == [.release(10)])
        #expect(grabs.ended(node: 10).isEmpty)
        #expect(grabs.heldNodes == [40])
    }

    @Test func aHandThatGrabsAgainLetsGoOfItsOldNode() {
        var grabs = HandGrabs()
        _ = grabs.began(node: 10, hands: [.left])

        // The release of node 10 was missed: the left hand cannot hold two nodes.
        #expect(grabs.began(node: 20, hands: [.left]) == [.release(10), .grab(20)])
        #expect(grabs.heldNodes == [20])
    }

    @Test func aNodePassesFromHandToHandWithoutBeingDropped() {
        var grabs = HandGrabs()
        _ = grabs.began(node: 10, hands: [.left])

        #expect(grabs.handedOff(node: 10, to: [.left, .right]).isEmpty)
        #expect(grabs.handedOff(node: 10, to: [.right]).isEmpty)
        #expect(grabs.node(heldBy: .right) == 10)
        #expect(grabs.node(heldBy: .left) == nil)
    }

    @Test func aLateEndDoesNotDropAQuickRegrab() {
        var grabs = HandGrabs()
        _ = grabs.began(node: 10, hands: [.left])
        #expect(grabs.released(node: 10) == [.release(10)])
        // Grabbed again before the end of the previous grab arrives.
        #expect(grabs.began(node: 10, hands: [.left]) == [.grab(10)])
        #expect(grabs.ended(node: 10).isEmpty)
        #expect(grabs.heldNodes == [10])
    }

    @Test func aCancelledGrabIsDropped() {
        var grabs = HandGrabs()
        _ = grabs.began(node: 10, hands: [.right])

        #expect(grabs.ended(node: 10) == [.release(10)])
        #expect(grabs.heldNodes.isEmpty)
    }
}

@MainActor
struct UntangleViewModelTests {
    @Test func platformPlacementIsClamped() {
        let viewModel = UntangleViewModel()
        viewModel.setTilt(10)

        #expect(viewModel.placement.tilt == PlayAreaPlacement.tiltRange.upperBound)
    }

    /// The island in its standard placement, optionally turned.
    private func islandOrbit(yaw: Float = 0) -> AnchoredOrbit {
        var island = IslandPlacement.standard
        island.yaw = yaw
        return AnchoredOrbit(path: .aroundTree, worldFromAnchor: island.transform)
    }

    @Test func storyStartsWithTheDragonBoundToTheTree() {
        let viewModel = UntangleViewModel(shape: .trefoil)
        // On the island the dragon cannot be grabbed: a tap only makes it angry.
        viewModel.grab(node: viewModel.config.nodeCount - 1)
        viewModel.update(deltaTime: 1.0 / 60.0, viewer: SIMD3(0, 1.15, 0), worldFromLocal: matrix_identity_float4x4,
                         orbit: islandOrbit())

        #expect(viewModel.phase == .captive)
        #expect(viewModel.userGrabbedNodes.isEmpty)
        #expect(viewModel.crossingPoints.isEmpty)
        #expect(viewModel.dragonOpacity == 1)

        viewModel.tapDragon()
        #expect(viewModel.phase == .alerted)
        #expect(viewModel.mood == .restless)

        // After the fit of anger it calms down and keeps circling: only the artifact brings it down.
        var elapsed: Float = 0
        while viewModel.phase == .alerted && elapsed < viewModel.alertDuration + 1 {
            viewModel.update(deltaTime: 1.0 / 60.0, viewer: SIMD3(0, 1.15, 0), worldFromLocal: matrix_identity_float4x4,
                             orbit: islandOrbit())
            elapsed += 1.0 / 60.0
        }
        #expect(viewModel.phase == .captive)
        #expect(viewModel.mood == .calm)
        #expect(elapsed >= viewModel.alertDuration - 0.05)
    }

    @Test func captiveDragonTurnsWithTheIsland() {
        let viewModel = UntangleViewModel(shape: .trefoil)
        let frame = { (yaw: Float, deltaTime: Float) in
            viewModel.update(deltaTime: deltaTime, viewer: SIMD3(0, 1.15, 0), worldFromLocal: matrix_identity_float4x4,
                             orbit: self.islandOrbit(yaw: yaw))
        }
        for _ in 0..<120 { frame(0, 1.0 / 60.0) }
        let before = viewModel.displayPositions
        // The island turns 90° in an instant (no time passes): the dragon must turn rigidly with it.
        frame(.pi / 2, 0)
        let turn = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 1, 0))
        let tree = IslandPlacement.standard.position
        let expected = before.map { tree + turn.act($0 - tree) }

        #expect(zip(viewModel.displayPositions, expected).allSatisfy { simd_distance($0, $1) < 0.001 })
    }

    @Test func callingTheDragonBringsItToThePuzzle() {
        let viewModel = UntangleViewModel(shape: .trefoil)
        var transform = float4x4(PlayAreaPlacement.seated.rotation)
        transform.columns.3 = SIMD4(PlayAreaPlacement.seated.position, 1)
        let orbit = islandOrbit(yaw: 0.7)
        let frame = { viewModel.update(deltaTime: 1.0 / 60.0, viewer: SIMD3(0, 1.15, 0), worldFromLocal: transform, orbit: orbit) }
        frame()
        viewModel.tapDragon()
        frame()
        let beforeCall = viewModel.displayPositions
        viewModel.callDragon()
        #expect(viewModel.phase == .approaching)
        // Leaving the island does not make the body jump (only the space it flies in changes).
        #expect(zip(viewModel.displayPositions, beforeCall).allSatisfy { simd_distance($0, $1) < 0.001 })

        var frames = 0
        while viewModel.phase != .untangling && frames < 60 * 30 {
            frame()
            frames += 1
        }

        #expect(viewModel.phase == .untangling)
        #expect(viewModel.crossingCount == 3)
        // Between the first pose and the simulated tangle there are no visible jumps.
        #expect(zip(viewModel.displayPositions, viewModel.nodePositions).allSatisfy { simd_distance($0, $1) < 0.03 })
    }

    @Test func leftAndRightHandsDragTwoPartsIndependently() {
        let viewModel = UntangleViewModel(shape: .trefoil)
        let frame = { viewModel.update(deltaTime: 1.0 / 60.0, viewer: SIMD3(0, 1.15, 0),
                                       worldFromLocal: matrix_identity_float4x4, orbit: self.islandOrbit()) }
        frame()
        viewModel.callDragon()
        while viewModel.phase != .untangling { frame() }

        let left = 20
        let right = viewModel.config.nodeCount - 1
        viewModel.manipulationBegan(node: left, hands: [.left])
        viewModel.manipulationBegan(node: right, hands: [.right])
        #expect(viewModel.userGrabbedNodes == [left, right])

        let leftStart = viewModel.nodePositions[left]
        let rightStart = viewModel.nodePositions[right]
        for _ in 0..<60 {
            viewModel.drag(node: left, to: leftStart + SIMD3(0, 0.05, 0))
            viewModel.drag(node: right, to: rightStart + SIMD3(0.04, 0, 0))
            frame()
        }
        // Each hand moved its own part, in its own direction.
        #expect(viewModel.nodePositions[left].y > leftStart.y + 0.02)
        #expect(viewModel.nodePositions[right].x > rightStart.x + 0.02)

        // The left hand lets go: the right one keeps holding and dragging.
        viewModel.manipulationReleased(node: left)
        viewModel.manipulationEnded(node: left)
        #expect(viewModel.userGrabbedNodes == [right])
        let beforeDrag = viewModel.nodePositions[right]
        for _ in 0..<30 {
            viewModel.drag(node: right, to: beforeDrag + SIMD3(0, 0.04, 0))
            frame()
        }
        #expect(viewModel.nodePositions[right].y > beforeDrag.y + 0.015)
        #expect(viewModel.handGrabs.summary == "R \(right)")
    }

    @Test func restartsResetTheDragonAndTheGame() {
        let viewModel = UntangleViewModel(shape: .trefoil)
        let frame = { viewModel.update(deltaTime: 1.0 / 60.0, viewer: SIMD3(0, 1.15, 0),
                                       worldFromLocal: matrix_identity_float4x4, orbit: self.islandOrbit()) }
        frame()
        viewModel.callDragon()
        while viewModel.phase != .untangling { frame() }

        viewModel.grab(node: viewModel.config.nodeCount - 1)
        viewModel.restartPuzzle()
        #expect(viewModel.phase == .untangling)
        #expect(viewModel.crossingCount == 3)
        #expect(viewModel.userGrabbedNodes.isEmpty)

        viewModel.rotateIsland(by: IslandPlacement.yawStep)
        viewModel.restartScene()
        #expect(viewModel.phase == .captive)
        #expect(!viewModel.isSolved && !viewModel.isFlying)
        #expect(viewModel.islandPlacement.yaw == IslandPlacement.yawStep)

        viewModel.resetGame()
        #expect(viewModel.islandPlacement == .standard)
        #expect(viewModel.placement == .seated)
    }
}
