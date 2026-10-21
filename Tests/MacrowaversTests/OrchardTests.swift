import simd
import Testing
@testable import Macrowavers

struct AppleShapeTests {
    @Test func closedAppleHasNoGapsAndOpenAppleLiftsEveryTurn() {
        let shape = AppleShape()
        let theta = 2 * Float.pi * 2.5
        #expect(shape.lift(theta: theta, opening: 0) == 0)
        #expect(shape.lift(theta: theta, opening: 1) > shape.lift(theta: theta - 2 * .pi, opening: 1))
        #expect(abs(shape.maxLift - shape.gapPerTurn * shape.turns) < 1e-6)
    }

    @Test func surfaceStaysInsideTheAppleProfile() {
        let shape = AppleShape()
        for step in 0...100 {
            let theta = shape.thetaStart + (shape.thetaEnd - shape.thetaStart) * Float(step) / 100
            let point = shape.point(theta: theta, radial: 1, vertical: 0.5, surface: .skin, opening: 0)
            #expect(simd_length(SIMD2(point.x, point.z)) <= shape.maxRadius + 1e-5)
            #expect(point.y >= 0 && point.y <= shape.height + 1e-5)
            let normal = shape.normal(theta: theta, radial: 1, vertical: 0.5, surface: .skin, opening: 0.5)
            #expect(abs(simd_length(normal) - 1) < 1e-3)
        }
    }

    @Test func swiftTypesMatchTheMetalShaderLayout() {
        // AppleSpiral.metal: VertexParams 16 bytes, OutVertex 2 × float3 (16 each), Uniforms 6 × 4 bytes.
        #expect(MemoryLayout<AppleVertexParams>.stride == 16)
        #expect(MemoryLayout<AppleVertex>.stride == 32)
        #expect(MemoryLayout<AppleVertex>.offset(of: \.normal) == 16)
        #expect(MemoryLayout<AppleUniforms>.size == 24)
    }
}

struct WormSwarmTests {
    /// Advances the swarm for `seconds`.
    private func run(_ swarm: inout WormSwarm, seconds: Float, opening: Float) {
        for _ in 0..<Int(seconds * 60) { swarm.update(deltaTime: 1.0 / 60.0, opening: opening) }
    }

    @Test func wormsHideWhileTheAppleIsClosed() {
        var swarm = WormSwarm(shape: AppleShape())
        run(&swarm, seconds: 2, opening: 0.1)

        #expect(swarm.worms.allSatisfy { $0.visibility == 0 })
        let caught = swarm.catchWorm(0)
        #expect(!caught)
    }

    @Test func wormsComeOutCrawlAndBurrow() {
        var swarm = WormSwarm(shape: AppleShape())
        run(&swarm, seconds: 0.5, opening: 1)
        #expect(swarm.worms.allSatisfy { $0.visibility == 1 })
        let start = swarm.worms[0].theta

        var sawBurrow = false
        for _ in 0..<(60 * 8) {
            swarm.update(deltaTime: 1.0 / 60.0, opening: 1)
            if swarm.worms[0].underground > 0 {
                sawBurrow = true
                // Underground it cannot be caught.
                #expect(!swarm.isCatchable(0))
            }
            #expect(swarm.crawlRange.contains(swarm.worms[0].theta))
        }
        #expect(sawBurrow)
        #expect(swarm.worms[0].theta != start)
    }

    @Test func eachCatchMakesTheOthersFaster() {
        var swarm = WormSwarm(shape: AppleShape(), settings: .init(burrowInterval: 100...101))
        run(&swarm, seconds: 0.5, opening: 1)
        let before = swarm.worms[1].theta
        run(&swarm, seconds: 0.1, opening: 1)
        let slowStep = abs(swarm.worms[1].theta - before)

        let caught = swarm.catchWorm(0)
        #expect(caught)
        let after = swarm.worms[1].theta
        run(&swarm, seconds: 0.1, opening: 1)
        let fastStep = abs(swarm.worms[1].theta - after)

        #expect(fastStep > slowStep * 1.2)
        #expect(swarm.caughtCount == 1)
    }
}

@MainActor
struct OrchardViewModelTests {
    /// Opens the focused apple and catches every worm as soon as it is out.
    private func clearWorms(_ orchard: OrchardViewModel) {
        orchard.setAppleOpening(1)
        for _ in 0..<(60 * 30) where orchard.caughtWorms < orchard.wormCount {
            orchard.update(deltaTime: 1.0 / 60.0)
            for index in 0..<orchard.wormCount { orchard.catchWorm(index) }
        }
    }

    private func id(of kind: FruitKind, in orchard: OrchardViewModel) -> Int {
        orchard.fruits.first { $0.kind == kind }?.id ?? -1
    }

    /// Opens the focused fruit whatever it is, so its orb comes out.
    private func open(_ orchard: OrchardViewModel) {
        switch orchard.focusedFruit?.kind {
        case .apple: clearWorms(orchard)
        case .pomegranate: orchard.setPomegranateOpening(1)
        case .orange:
            for petal in 0..<OrchardViewModel.orangePetals { orchard.setOrangePeel(petal: petal, progress: 1) }
        case .pineapple: orchard.chopPineapple()
        case nil: break
        }
    }

    /// Picks a fruit, opens it and waits for its ingredient to join the orbit.
    private func harvest(_ fruit: Int, into orchard: OrchardViewModel) {
        orchard.focus(fruit: fruit)
        open(orchard)
        run(orchard, seconds: OrchardViewModel.orbRiseDuration + OrchardViewModel.orbOrbitDelay + 0.1)
    }

    private func run(_ orchard: OrchardViewModel, seconds: Float) {
        for _ in 0..<Int(seconds * 60) { orchard.update(deltaTime: 1.0 / 60.0) }
    }

    @Test func treeHasEveryKindOfFruit() {
        let orchard = OrchardViewModel()
        #expect(orchard.fruits.map(\.kind) == [.apple, .apple, .apple, .pomegranate, .orange, .pineapple])
        #expect(orchard.orbs.allSatisfy { $0 == .sealed })
    }

    @Test func clearingTheWormsFreesTheApplesOrb() {
        let orchard = OrchardViewModel()
        #expect(orchard.focus(fruit: 0))
        // Only one fruit at a time.
        #expect(!orchard.focus(fruit: 1))
        clearWorms(orchard)
        #expect(orchard.caughtWorms == orchard.wormCount)
        #expect(orchard.orbs[0] == .revealed)
        #expect(orchard.orbs[1] == .sealed)
    }

    @Test func everyFruitOpensItsOwnWay() {
        let orchard = OrchardViewModel()
        let pomegranate = id(of: .pomegranate, in: orchard)
        orchard.focus(fruit: pomegranate)
        orchard.setPomegranateOpening(0.5)
        #expect(orchard.orbs[pomegranate] == .sealed)
        orchard.setPomegranateOpening(1)
        #expect(orchard.pomegranateBurst && orchard.orbs[pomegranate] == .revealed)
        orchard.back()

        let orange = id(of: .orange, in: orchard)
        orchard.focus(fruit: orange)
        for petal in 0..<(OrchardViewModel.orangePetals - 1) { orchard.setOrangePeel(petal: petal, progress: 1) }
        // Five petals out of six: still closed.
        #expect(orchard.orbs[orange] == .sealed && !orchard.isFocusedFruitExplored)
        orchard.setOrangePeel(petal: OrchardViewModel.orangePetals - 1, progress: OrchardViewModel.peeledPetal)
        #expect(orchard.orbs[orange] == .revealed && orchard.isFocusedFruitExplored)
        // Other fruits' gestures do nothing to an orange.
        orchard.setAppleOpening(1)
        orchard.chopPineapple()
        #expect(orchard.appleOpening == 0 && !orchard.pineappleChopped)
        orchard.back()

        let pineapple = id(of: .pineapple, in: orchard)
        orchard.focus(fruit: pineapple)
        orchard.chopPineapple()
        #expect(orchard.pineappleChopped && orchard.orbs[pineapple] == .revealed)
    }

    @Test func leavingAFruitEarlyKeepsItsOrbForLater() {
        let orchard = OrchardViewModel()
        orchard.focus(fruit: 0)
        orchard.setAppleOpening(1)
        orchard.back()
        #expect(orchard.orbs[0] == .sealed)
        #expect(orchard.appleOpening == 0)

        // Back at the apple before its freed orb has joined the orbit: it is still there, and no worms are left.
        orchard.focus(fruit: 0)
        clearWorms(orchard)
        orchard.back()
        orchard.focus(fruit: 0)
        #expect(orchard.orbs[0] == .revealed)
        #expect(orchard.caughtWorms == orchard.wormCount)
    }

    @Test func foundIngredientRisesThenJoinsTheOrbitAndTheFruitGoesBack() {
        let orchard = OrchardViewModel()
        let orange = id(of: .orange, in: orchard)
        orchard.focus(fruit: orange)
        // Not out yet: it cannot be tapped into orbit.
        #expect(!orchard.collectOrb(fruit: orange))
        open(orchard)
        #expect(!orchard.collectOrb(fruit: orange))
        // Risen: the player sees it float above the fruit for a moment.
        run(orchard, seconds: OrchardViewModel.orbRiseDuration + 0.05)
        #expect(orchard.orbs[orange] == .revealed && orchard.focusedFruitID == orange)
        // Then it joins the orbit by itself and the fruit goes back to the tree.
        run(orchard, seconds: OrchardViewModel.orbOrbitDelay)
        #expect(orchard.orbs[orange] == .orbiting(slot: 0))
        #expect(orchard.elixir.orbitingCount == 1)
        #expect(orchard.focusedFruitID == nil)
    }

    @Test func tappingTheRisenIngredientSendsItAtOnce() {
        let orchard = OrchardViewModel()
        let pineapple = id(of: .pineapple, in: orchard)
        orchard.focus(fruit: pineapple)
        open(orchard)
        run(orchard, seconds: OrchardViewModel.orbRiseDuration + 0.05)
        #expect(orchard.collectOrb(fruit: pineapple))
        #expect(orchard.orbs[pineapple] == .orbiting(slot: 0) && orchard.focusedFruitID == nil)
        #expect(!orchard.collectOrb(fruit: pineapple))
    }

    @Test func ingredientFreedJustBeforeGoingBackStillJoins() {
        let orchard = OrchardViewModel()
        let orange = id(of: .orange, in: orchard)
        orchard.focus(fruit: orange)
        open(orchard)
        orchard.back()
        run(orchard, seconds: OrchardViewModel.orbRiseDuration + OrchardViewModel.orbOrbitDelay + 0.1)
        #expect(orchard.orbs[orange] == .orbiting(slot: 0))
    }

    @Test func emptyFruitStaysUntilThePlayerSendsItBack() {
        let orchard = OrchardViewModel()
        let pineapple = id(of: .pineapple, in: orchard)
        harvest(pineapple, into: orchard)
        orchard.focus(fruit: pineapple)
        #expect(orchard.isFocusedFruitEmpty)
        orchard.chopPineapple()
        // Its ingredient already orbits: nothing comes out, and the fruit does not leave by itself.
        #expect(orchard.orbs[pineapple] == .orbiting(slot: 0))
        run(orchard, seconds: 3)
        #expect(orchard.focusedFruitID == pineapple)
        orchard.back()
        #expect(orchard.focusedFruitID == nil)
    }

    @Test func fullOrbitTakesNoMoreIngredients() {
        let orchard = OrchardViewModel()
        for fruit in 0..<Elixir.ingredientCount { harvest(fruit, into: orchard) }
        #expect(orchard.elixir.state == .ready)
        let pineapple = id(of: .pineapple, in: orchard)
        orchard.focus(fruit: pineapple)
        open(orchard)
        run(orchard, seconds: 3)
        // It keeps floating above its fruit.
        #expect(orchard.orbs[pineapple] == .revealed && orchard.focusedFruitID == pineapple)
        #expect(!orchard.collectOrb(fruit: pineapple))
    }

    @Test func elixirNeedsThreeIngredientsThenFliesToTheDragon() {
        let orchard = OrchardViewModel()
        harvest(id(of: .orange, in: orchard), into: orchard)
        harvest(id(of: .pineapple, in: orchard), into: orchard)
        #expect(!orchard.brewElixir())
        harvest(id(of: .pomegranate, in: orchard), into: orchard)
        #expect(orchard.brewElixir())
        #expect(orchard.elixir.state == .fusing)

        run(orchard, seconds: Elixir.fusingDuration + 0.1)
        #expect(orchard.elixir.state == .brewed)
        #expect(orchard.orbs.filter { $0 == .spent }.count == Elixir.ingredientCount)
        run(orchard, seconds: Elixir.brewedHold + 0.1)
        #expect(orchard.elixir.state == .flying)
        // While it flies no fruit can be picked.
        #expect(!orchard.focus(fruit: 0))

        orchard.elixirDelivered()
        #expect(orchard.elixir.state == .delivered)
        orchard.reset()
        #expect(orchard.elixir == Elixir())
        #expect(orchard.orbs.allSatisfy { $0 == .sealed })
    }

    @Test func elixirWaitsInFrontOfThePlayerWhenTheDragonIsGone() {
        let orchard = OrchardViewModel()
        for fruit in 0..<Elixir.ingredientCount { harvest(fruit, into: orchard) }
        orchard.isDragonOnIsland = false
        orchard.brewElixir()
        run(orchard, seconds: Elixir.fusingDuration + Elixir.brewedHold + 1)
        #expect(orchard.elixir.state == .brewed)
    }

    @Test func brewingSendsTheCloseFruitBack() {
        let orchard = OrchardViewModel()
        for fruit in 0..<Elixir.ingredientCount { harvest(fruit, into: orchard) }
        orchard.focus(fruit: id(of: .orange, in: orchard))
        #expect(orchard.brewElixir())
        #expect(orchard.focusedFruitID == nil)
    }
}
