import simd
import Testing
@testable import Macrowavers

struct SceneFocusTests {
    private let phases: [DragonPhase] = [.captive, .alerted, .receivingElixir, .approaching, .landing, .untangling, .free,
                                         .gone]

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

    @Test func onlyTheKnotFocusesOnTheDragon() {
        #expect(phases.filter(\.focusesOnDragon) == [.landing, .untangling])
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
