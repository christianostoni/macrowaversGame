import simd
import Testing
@testable import Macrowavers

struct SceneFocusTests {
    private let phases: [DragonPhase] = [.captive, .alerted, .approaching, .landing, .untangling, .free, .gone]

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
}
