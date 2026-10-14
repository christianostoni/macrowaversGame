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

        // Si alza finché il limite di tensione lo permette, mentre l'altra mano tiene la coda.
        #expect(simulation.positions[20].y > restingHeight + 0.01)
        #expect(simulation.isGrabbed(config.nodeCount - 1))
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
        // Nessuno scatto: a 0,35 m/s un nodo si sposta di meno di 1 cm per frame.
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
}

@MainActor
struct UntangleViewModelTests {
    @Test func platformPlacementIsClamped() {
        let viewModel = UntangleViewModel()
        viewModel.setTilt(10)

        #expect(viewModel.placement.tilt == PlayAreaPlacement.tiltRange.upperBound)
    }

    @Test func storyStartsWithTheDragonBoundToTheTree() {
        let viewModel = UntangleViewModel(shape: .trefoil)
        let orbit = OrbitPath.aroundTree.placed(at: IslandPlacement.standard.position, scale: IslandPlacement.standard.scale)
        // Sull'isola il drago non si afferra: solo il tocco lo chiama.
        viewModel.grab(node: viewModel.config.nodeCount - 1)
        viewModel.update(deltaTime: 1.0 / 60.0, viewer: SIMD3(0, 1.15, 0), worldFromLocal: matrix_identity_float4x4, orbit: orbit)

        #expect(viewModel.phase == .captive)
        #expect(viewModel.userGrabbedNodes.isEmpty)
        #expect(viewModel.crossingPoints.isEmpty)
        #expect(viewModel.dragonOpacity == 1)
    }

    @Test func tapBringsTheDragonToThePuzzle() {
        let viewModel = UntangleViewModel(shape: .trefoil)
        let orbit = OrbitPath.aroundTree.placed(at: IslandPlacement.standard.position, scale: IslandPlacement.standard.scale)
        var transform = float4x4(PlayAreaPlacement.seated.rotation)
        transform.columns.3 = SIMD4(PlayAreaPlacement.seated.position, 1)
        let frame = { viewModel.update(deltaTime: 1.0 / 60.0, viewer: SIMD3(0, 1.15, 0), worldFromLocal: transform, orbit: orbit) }
        frame()
        viewModel.tapDragon()
        #expect(viewModel.phase == .approaching)

        var frames = 0
        while viewModel.phase != .untangling && frames < 60 * 30 {
            frame()
            frames += 1
        }

        #expect(viewModel.phase == .untangling)
        #expect(viewModel.crossingCount == 3)
        // Tra la prima posa e il groviglio simulato non ci sono salti visibili.
        #expect(zip(viewModel.displayPositions, viewModel.nodePositions).allSatisfy { simd_distance($0, $1) < 0.03 })
    }

    @Test func restartAndPlayAgainResetTheDragon() {
        let viewModel = UntangleViewModel(shape: .trefoil)
        let orbit = OrbitPath.aroundTree.placed(at: IslandPlacement.standard.position, scale: IslandPlacement.standard.scale)
        let frame = { viewModel.update(deltaTime: 1.0 / 60.0, viewer: SIMD3(0, 1.15, 0),
                                       worldFromLocal: matrix_identity_float4x4, orbit: orbit) }
        frame()
        viewModel.tapDragon()
        while viewModel.phase != .untangling { frame() }

        viewModel.grab(node: viewModel.config.nodeCount - 1)
        viewModel.restartPuzzle()
        #expect(viewModel.phase == .untangling)
        #expect(viewModel.crossingCount == 3)
        #expect(viewModel.userGrabbedNodes.isEmpty)

        viewModel.playAgain()
        #expect(viewModel.phase == .captive)
        #expect(!viewModel.isSolved && !viewModel.isFlying)
    }
}
