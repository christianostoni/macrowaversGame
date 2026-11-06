import simd
import Testing
@testable import Macrowavers

struct SceneFocusTests {
    private let phases: [DragonPhase] = [.captive, .alerted, .receivingElixir, .approaching, .landing, .untangling, .free]

    @Test func aFruitCloseFadesTheIslandAndTheDragon() {
        let focus = SceneFocus(isFruitFocused: true, isElixirFlying: false, phase: .captive)

        #expect(focus == .fruit)
        #expect(focus.opacity(of: .island) == SceneFocus.dimmedOpacity)
        #expect(focus.opacity(of: .dragon) == SceneFocus.dimmedOpacity)
    }

    @Test func untanglingKeepsOnlyTheDragonVisible() {
        for phase in [DragonPhase.landing, .untangling] {
            let focus = SceneFocus(isFruitFocused: false, isElixirFlying: false, phase: phase)

            #expect(focus == .dragon)
            #expect(focus.opacity(of: .island) == SceneFocus.dimmedOpacity)
            #expect(focus.opacity(of: .dragon) == 1)
        }
    }

    @Test func exploringRestoresEverything() {
        for phase in phases where !phase.focusesOnDragon {
            let focus = SceneFocus(isFruitFocused: false, isElixirFlying: false, phase: phase)

            #expect(focus == .none)
            #expect(focus.opacity(of: .island) == 1)
            #expect(focus.opacity(of: .dragon) == 1)
        }
    }

    @Test func theSpeakingDragonKeepsOnlyItselfVisible() {
        // Free, the dragon thanks the player (story screens 4 and 5): the island fades back behind it.
        let focus = SceneFocus(isFruitFocused: false, isElixirFlying: false, phase: .free, isDragonSpeaking: true)

        #expect(focus == .dragon)
        #expect(focus.opacity(of: .island) == SceneFocus.dimmedOpacity)
        #expect(focus.opacity(of: .dragon) == 1)
    }

    @Test func theFlyingElixirBringsTheSceneBack() {
        // The player follows the elixir to the dragon: nothing stays faded while it flies.
        let focus = SceneFocus(isFruitFocused: true, isElixirFlying: true, phase: .alerted)

        #expect(focus == .none)
    }

    @Test func onlyTheKnotAndTheFreedDragonFocusOnTheDragon() {
        #expect(phases.filter(\.focusesOnDragon) == [.landing, .untangling, .free])
    }

    @Test func theIslandStaysBackTheMomentTheDragonIsFreed() {
        // The dragon is freed a frame before the story makes it speak: the island must not start to come back.
        for isDragonSpeaking in [false, true] {
            let focus = SceneFocus(isFruitFocused: false, isElixirFlying: false, phase: .free,
                                   isDragonSpeaking: isDragonSpeaking)

            #expect(focus == .dragon)
            #expect(focus.opacity(of: .island) == SceneFocus.dimmedOpacity)
        }
    }
}

struct IslandPlacementTests {
    @Test func islandIsAtLeastItsOriginalSize() {
        // It was 0.8 before the grass was lowered: lowering it must not shrink it.
        #expect(IslandPlacement.standard.scale >= 0.8)
    }

    @Test func grassStaysAtTableHeightWhateverTheScale() {
        for scale: Float in [0.5, 1, 1.5] {
            var placement = IslandPlacement.standard
            placement.scale = scale
            placement.yaw = 0.7
            let grass = placement.transform * SIMD4<Float>(0, 0, 0, 1)

            #expect(abs(grass.y - IslandPlacement.grassHeight) < 1e-5)
            #expect(abs(IslandPlacement.grassHeight - 0.6) < 1e-5)
            // Positive, uniform scale: no mirroring, no squashing.
            #expect(simd_determinant(placement.transform) > 0)
            let columns = [placement.transform.columns.0, placement.transform.columns.1, placement.transform.columns.2]
            #expect(columns.allSatisfy { abs(simd_length(SIMD3($0.x, $0.y, $0.z)) - scale) < 1e-5 })
        }
    }

    /// Where the point of the island facing `viewer` goes after a turn.
    private func facingSide(after turn: Float, of placement: IslandPlacement, viewer: SIMD3<Float>) -> SIMD3<Float> {
        var offset = viewer - placement.position
        offset.y = 0
        return simd_quatf(angle: turn, axis: SIMD3(0, 1, 0)).act(simd_normalize(offset))
    }

    @Test func theSideFacingThePlayerFollowsTheHand() {
        let placement = IslandPlacement.standard
        let viewer = SIMD3<Float>(0, 1.15, 0)   // seated player at the origin
        let right = SIMD3<Float>(0.1, 0, 0)
        let turn = placement.spinAngle(handMovement: right, viewer: viewer)

        #expect(turn > 0)
        // The front of the island moves right, with the hand.
        #expect(facingSide(after: turn, of: placement, viewer: viewer).x > 0)
        #expect(abs(placement.spinAngle(handMovement: -right, viewer: viewer) + turn) < 1e-6)
        #expect(abs(turn - 0.1 / IslandPlacement.spinDistance) < 1e-5)
    }

    @Test func handMovementTowardsTheIslandOrUpDoesNotTurnIt() {
        let placement = IslandPlacement.standard
        let viewer = SIMD3<Float>(0, 1.15, 0)   // seated player at the origin
        #expect(abs(placement.spinAngle(handMovement: SIMD3(0, 0, -0.2), viewer: viewer)) < 1e-6)
        #expect(abs(placement.spinAngle(handMovement: SIMD3(0, 0.2, 0), viewer: viewer)) < 1e-6)
    }

    @Test func fromAnySideOfTheIslandTheFacingSideFollowsTheHand() {
        let placement = IslandPlacement.standard
        // The player walks around the island: to its left, behind it, to its right.
        for viewer in [SIMD3<Float>(-2.5, 1.2, -2.8), SIMD3(0, 1.2, -5.5), SIMD3(2.5, 1.2, -2.8)] {
            var towardsIsland = placement.position - viewer
            towardsIsland.y = 0
            // The player's right: forward × up.
            let playersRight = simd_normalize(simd_cross(towardsIsland, SIMD3(0, 1, 0)))
            let turn = placement.spinAngle(handMovement: 0.1 * playersRight, viewer: viewer)

            #expect(turn > 0)
            #expect(simd_dot(facingSide(after: turn, of: placement, viewer: viewer), playersRight) > 0)
        }
    }

    @Test func aPlayerAboveTheTrunkStillGetsAFiniteTurn() {
        var viewer = IslandPlacement.standard.position
        viewer.y += 1
        let turn = IslandPlacement.standard.spinAngle(handMovement: SIMD3(0.1, 0, 0), viewer: viewer)
        #expect(turn.isFinite)
    }
}

/// Carrying the island by its grab bar, like a window.
struct IslandCarryTests {
    private let viewer = SIMD3<Float>(0, 1.15, 0)   // seated player at the origin
    private let hand = SIMD3<Float>(0, 0.9, -0.45)  // pinching the bar, in front of the chest

    private func distance(_ placement: IslandPlacement) -> Float {
        simd_length(SIMD2(placement.position.x - viewer.x, placement.position.z - viewer.z))
    }

    @Test func aStillHandLeavesItWhereItIs() {
        let carried = IslandPlacement.standard.carried(from: hand, to: hand, viewer: viewer)
        #expect(simd_distance(carried.position, IslandPlacement.standard.position) < 1e-5)
        #expect(abs(carried.yaw - IslandPlacement.standard.yaw) < 1e-6)
    }

    @Test func itGoesWhereTheHandPointsAndKeepsItsFaceToThePlayer() {
        let start = IslandPlacement.standard
        // The hand swings 20° to the player's left around them, at the same reach.
        let angle: Float = 20 * .pi / 180
        let reach = simd_length(SIMD2(hand.x, hand.z))
        let swung = SIMD3(-reach * sin(angle), hand.y, -reach * cos(angle))
        let carried = start.carried(from: hand, to: swung, viewer: viewer)

        #expect(carried.position.x < -0.9)   // 2.8 m · sin 20° ≈ 0.96 m to the left
        #expect(abs(distance(carried) - distance(start)) < 1e-4)
        // Turned with the swing: the same side still faces the player.
        #expect(abs(carried.yaw - angle) < 1e-4)
    }

    @Test func pushedItGoesFartherThanTheHandAndStaysOnTheFloor() {
        let start = IslandPlacement.standard
        let pushed = start.carried(from: hand, to: hand + SIMD3(0, 0.3, -0.2), viewer: viewer)

        #expect(abs(distance(pushed) - (distance(start) + IslandPlacement.pushGain * 0.2)) < 1e-4)
        #expect(pushed.position.y == start.position.y)
        #expect(abs(pushed.yaw - start.yaw) < 1e-5)
    }

    @Test func itNeverLandsOnThePlayerNorLeavesTheRoom() {
        let start = IslandPlacement.standard
        let pulled = start.carried(from: hand, to: SIMD3(0, 0.9, -0.05), viewer: viewer)
        let thrown = start.carried(from: hand, to: SIMD3(0, 0.9, -3), viewer: viewer)

        #expect(abs(distance(pulled) - IslandPlacement.distanceRange.lowerBound) < 1e-4)
        #expect(abs(distance(thrown) - IslandPlacement.distanceRange.upperBound) < 1e-4)
    }

    @Test @MainActor func theViewModelTakesTheCarriedPlacement() {
        let viewModel = UntangleViewModel()
        let carried = IslandPlacement.standard.carried(from: hand, to: hand + SIMD3(0.1, 0, -0.1), viewer: viewer)
        viewModel.moveIsland(to: carried, viewer: viewer)
        #expect(viewModel.islandPlacement.position == carried.position)
        #expect(abs(viewModel.islandPlacement.yaw - carried.yaw) < 1e-5)

        viewModel.resetGame()
        #expect(viewModel.islandPlacement == .standard)
        #expect(viewModel.placement == .seated)
    }

    @Test func theStandardIslandKeepsTheSeatedPlayArea() {
        let playArea = PlayAreaPlacement.seated.facing(island: .standard, viewer: viewer)
        #expect(simd_distance(playArea.position, PlayAreaPlacement.seated.position) < 1e-5)
        #expect(abs(playArea.yaw - PlayAreaPlacement.seated.yaw) < 1e-6)
        #expect(playArea.tilt == PlayAreaPlacement.seated.tilt)
    }

    @Test @MainActor func theDragonComesToCoilOnTheWayToTheCarriedIsland() {
        let viewModel = UntangleViewModel()
        // Swung 90° to the player's left: the island stands at their left, 2.8 m away.
        let left = SIMD3<Float>(-0.45, hand.y, 0)
        let carried = IslandPlacement.standard.carried(from: hand, to: left, viewer: viewer)
        viewModel.moveIsland(to: carried, viewer: viewer)

        let playArea = viewModel.placement
        #expect(abs(playArea.position.x + 0.6) < 1e-4)
        #expect(abs(playArea.position.z) < 1e-4)
        #expect(playArea.position.y == PlayAreaPlacement.seated.position.y)
        // Its far edge (−Z at yaw 0) points at the island.
        let farEdge = simd_quatf(angle: playArea.yaw, axis: SIMD3(0, 1, 0)).act(SIMD3(0, 0, -1))
        #expect(simd_distance(farEdge, SIMD3(-1, 0, 0)) < 1e-4)
    }

    @Test @MainActor func onceCalledTheDragonKeepsItsKnotWhereItWas() {
        let viewModel = UntangleViewModel()
        let orbit = AnchoredOrbit(path: .aroundTree, worldFromAnchor: IslandPlacement.standard.transform)
        viewModel.update(deltaTime: 1 / 90, viewer: viewer, worldFromLocal: matrix_identity_float4x4, orbit: orbit)
        viewModel.callDragon()
        #expect(viewModel.phase == .approaching)

        let carried = IslandPlacement.standard.carried(from: hand, to: SIMD3(-0.45, hand.y, 0), viewer: viewer)
        viewModel.moveIsland(to: carried, viewer: viewer)
        #expect(viewModel.islandPlacement.position == carried.position)
        #expect(viewModel.placement == .seated)
    }
}
