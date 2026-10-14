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

    @Test func firstClearedAppleFreesTheArtifact() {
        let orchard = OrchardViewModel(apples: 3, pomegranates: 1)
        #expect(orchard.focus(fruit: 0))
        #expect(orchard.artifact == .guarded)
        // Only one fruit at a time.
        #expect(!orchard.focus(fruit: 1))

        clearWorms(orchard)
        #expect(orchard.caughtWorms == orchard.wormCount)
        #expect(orchard.artifact == .revealed)
        #expect(orchard.artifactFruitID == 0)
    }

    @Test func leavingAnAppleEarlyKeepsTheArtifactForTheNextOne() {
        let orchard = OrchardViewModel()
        orchard.focus(fruit: 0)
        orchard.back()
        #expect(orchard.artifact == .hidden)

        orchard.focus(fruit: 1)
        clearWorms(orchard)
        #expect(orchard.artifact == .revealed)
        #expect(orchard.artifactFruitID == 1)

        // Other apples only have worms; the freed one keeps its artifact.
        orchard.back()
        orchard.focus(fruit: 2)
        clearWorms(orchard)
        #expect(orchard.artifactFruitID == 1)
        #expect(!orchard.useArtifact())
        orchard.back()
        orchard.focus(fruit: 1)
        #expect(orchard.caughtWorms == orchard.wormCount)
        #expect(orchard.useArtifact())
    }

    @Test func artifactFliesToTheDragonAndTheFruitGoesBack() {
        let orchard = OrchardViewModel()
        orchard.focus(fruit: 0)
        clearWorms(orchard)
        #expect(orchard.useArtifact())
        #expect(orchard.artifact == .flying)
        // While it flies no fruit can be picked.
        orchard.back()
        #expect(!orchard.focus(fruit: 1))

        orchard.artifactDelivered()
        #expect(orchard.artifact == .used)
        #expect(orchard.focusedFruitID == nil)

        orchard.reset()
        #expect(orchard.artifact == .hidden)
    }

    @Test func wrongFruitStaysUntilThePlayerSendsItBack() {
        let orchard = OrchardViewModel(apples: 2, pomegranates: 1)
        // Pomegranate: never the artifact, but it does not leave by itself.
        let pomegranate = orchard.fruits.first { $0.kind == .pomegranate }?.id ?? -1
        orchard.focus(fruit: pomegranate)
        orchard.setPomegranateOpening(1)
        for _ in 0..<(60 * 20) { orchard.update(deltaTime: 1.0 / 60.0) }
        #expect(orchard.isFocusedFruitEmpty && orchard.isFocusedFruitExplored)
        #expect(orchard.focusedFruitID == pomegranate)
        orchard.back()
        #expect(orchard.focusedFruitID == nil)

        // Second apple after the artifact came out of the first: empty, stays until sent back.
        orchard.focus(fruit: 0)
        #expect(!orchard.isFocusedFruitEmpty)
        clearWorms(orchard)
        orchard.back()
        orchard.focus(fruit: 1)
        orchard.setAppleOpening(1)
        for _ in 0..<(60 * 20) { orchard.update(deltaTime: 1.0 / 60.0) }
        #expect(orchard.isFocusedFruitEmpty)
        #expect(orchard.focusedFruitID == 1)
        #expect(orchard.artifact == .revealed)
    }

    @Test func pomegranateBurstsButHasNoArtifact() {
        let orchard = OrchardViewModel(apples: 1, pomegranates: 1)
        let pomegranate = orchard.fruits.first { $0.kind == .pomegranate }
        #expect(pomegranate != nil)
        orchard.focus(fruit: pomegranate?.id ?? -1)
        #expect(orchard.artifact == .hidden)
        orchard.setAppleOpening(1)
        #expect(orchard.appleOpening == 0)

        orchard.setPomegranateOpening(0.5)
        #expect(!orchard.pomegranateBurst)
        orchard.setPomegranateOpening(1)
        #expect(orchard.pomegranateBurst)
    }
}
