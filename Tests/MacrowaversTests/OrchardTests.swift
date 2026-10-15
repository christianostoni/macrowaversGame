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
        case .banana:
            for strip in 0..<OrchardViewModel.bananaStrips { orchard.setBananaPeel(strip: strip, progress: 1) }
        case .pineapple: orchard.chopPineapple()
        case nil: break
        }
    }

    /// Picks a fruit, opens it and carries its orb into the kalash.
    private func harvest(_ fruit: Int, into orchard: OrchardViewModel) {
        orchard.focus(fruit: fruit)
        open(orchard)
        orchard.grabOrb(fruit: fruit)
        orchard.releaseOrb(fruit: fruit, intoKalash: true)
    }

    private func run(_ orchard: OrchardViewModel, seconds: Float) {
        for _ in 0..<Int(seconds * 60) { orchard.update(deltaTime: 1.0 / 60.0) }
    }

    @Test func treeHasEveryKindOfFruit() {
        let orchard = OrchardViewModel()
        #expect(orchard.fruits.map(\.kind) == [.apple, .apple, .apple, .pomegranate, .banana, .pineapple])
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

        let banana = id(of: .banana, in: orchard)
        orchard.focus(fruit: banana)
        for strip in 0..<(OrchardViewModel.bananaStrips - 1) { orchard.setBananaPeel(strip: strip, progress: 1) }
        // Three strips out of four: still closed.
        #expect(orchard.orbs[banana] == .sealed && !orchard.isFocusedFruitExplored)
        orchard.setBananaPeel(strip: OrchardViewModel.bananaStrips - 1, progress: OrchardViewModel.peeledStrip)
        #expect(orchard.orbs[banana] == .revealed && orchard.isFocusedFruitExplored)
        // Other fruits' gestures do nothing to a banana.
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

        // A freed orb waits above its fruit; back at the apple there are no worms left.
        orchard.focus(fruit: 0)
        clearWorms(orchard)
        orchard.back()
        orchard.focus(fruit: 0)
        #expect(orchard.orbs[0] == .revealed)
        #expect(orchard.caughtWorms == orchard.wormCount)
    }

    @Test func orbDroppedIntoTheKalashSendsTheFruitBack() {
        let orchard = OrchardViewModel()
        let banana = id(of: .banana, in: orchard)
        orchard.focus(fruit: banana)
        // Not out yet: it cannot be grabbed.
        #expect(!orchard.grabOrb(fruit: banana))
        open(orchard)
        #expect(orchard.grabOrb(fruit: banana))
        // Let go away from the kalash: it floats back above the fruit.
        #expect(!orchard.releaseOrb(fruit: banana, intoKalash: false))
        #expect(orchard.orbs[banana] == .revealed && orchard.focusedFruitID == banana)

        orchard.grabOrb(fruit: banana)
        #expect(orchard.releaseOrb(fruit: banana, intoKalash: true))
        #expect(orchard.orbs[banana] == .stored(slot: 0))
        #expect(orchard.kalash.storedCount == 1)
        #expect(orchard.focusedFruitID == nil)
    }

    @Test func emptyFruitStaysUntilThePlayerSendsItBack() {
        let orchard = OrchardViewModel()
        let pineapple = id(of: .pineapple, in: orchard)
        harvest(pineapple, into: orchard)
        orchard.focus(fruit: pineapple)
        #expect(orchard.isFocusedFruitEmpty)
        orchard.chopPineapple()
        // Its orb is in the kalash: nothing comes out, and the fruit does not leave by itself.
        #expect(orchard.orbs[pineapple] == .stored(slot: 0))
        run(orchard, seconds: 3)
        #expect(orchard.focusedFruitID == pineapple)
        orchard.back()
        #expect(orchard.focusedFruitID == nil)
    }

    @Test func fullKalashTakesNoMoreOrbs() {
        let orchard = OrchardViewModel()
        for fruit in 0..<Kalash.capacity { harvest(fruit, into: orchard) }
        #expect(orchard.kalash.spell == .ready)
        let pineapple = id(of: .pineapple, in: orchard)
        orchard.focus(fruit: pineapple)
        open(orchard)
        orchard.grabOrb(fruit: pineapple)
        #expect(!orchard.releaseOrb(fruit: pineapple, intoKalash: true))
        #expect(orchard.orbs[pineapple] == .revealed)
    }

    @Test func spellNeedsThreeOrbsThenFliesToTheDragon() {
        let orchard = OrchardViewModel()
        harvest(id(of: .banana, in: orchard), into: orchard)
        harvest(id(of: .pineapple, in: orchard), into: orchard)
        #expect(!orchard.castSpell())
        harvest(id(of: .pomegranate, in: orchard), into: orchard)
        #expect(orchard.castSpell())
        #expect(orchard.kalash.spell == .forming)

        run(orchard, seconds: Kalash.formingDuration + 0.1)
        #expect(orchard.kalash.spell == .formed)
        #expect(orchard.orbs.filter { $0 == .spent }.count == Kalash.capacity)
        run(orchard, seconds: Kalash.formedHold + 0.1)
        #expect(orchard.kalash.spell == .flying)
        // While it flies no fruit can be picked.
        #expect(!orchard.focus(fruit: 0))

        orchard.spellDelivered()
        #expect(orchard.kalash.spell == .delivered)
        orchard.reset()
        #expect(orchard.kalash == Kalash())
        #expect(orchard.orbs.allSatisfy { $0 == .sealed })
    }

    @Test func spellWaitsAboveTheKalashWhenTheDragonIsGone() {
        let orchard = OrchardViewModel()
        for fruit in 0..<Kalash.capacity { harvest(fruit, into: orchard) }
        orchard.isDragonOnIsland = false
        orchard.castSpell()
        run(orchard, seconds: Kalash.formingDuration + Kalash.formedHold + 1)
        #expect(orchard.kalash.spell == .formed)
    }

    @Test func spellFlyingSendsTheCloseFruitBack() {
        let orchard = OrchardViewModel()
        for fruit in 0..<Kalash.capacity { harvest(fruit, into: orchard) }
        orchard.castSpell()
        orchard.focus(fruit: id(of: .banana, in: orchard))
        run(orchard, seconds: Kalash.formingDuration + Kalash.formedHold + 0.2)
        #expect(orchard.kalash.spell == .flying)
        #expect(orchard.focusedFruitID == nil)
    }
}
