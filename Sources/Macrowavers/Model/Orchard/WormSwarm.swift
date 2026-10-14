import Foundation
import simd

/// The worms living in an apple: the mini-challenge that guards the artifact.
///
/// Behaviour (tuned to stay easy, but never static):
/// - they **crawl** along the top of the spiral slices, turning back at the ends and drifting towards the
///   edge and back;
/// - every few seconds one **burrows** into the flesh for about a second: while hidden it cannot be caught;
/// - each worm caught makes the others **faster** (they get nervous);
/// - while the apple is almost closed (slices too tight) they all hide.
/// Pure logic: positions come from `AppleShape`, so it is testable without RealityKit.
struct WormSwarm {
    struct Settings {
        var count = 3
        /// Crawl speed along the spiral (radians per second).
        var crawlSpeed: Float = 0.45
        /// Extra speed for every worm already caught (0.3 = +30%).
        var speedUpPerCatch: Float = 0.3
        /// Seconds between two burrows of the same worm.
        var burrowInterval: ClosedRange<Float> = 3.5...6
        /// Seconds spent underground.
        var burrowDuration: Float = 1.1
        /// Seconds to pop out of / sink into the flesh.
        var emergeDuration: Float = 0.25
        /// Below this opening the slices are too close: the worms stay hidden.
        var minimumOpening: Float = 0.35
    }

    struct Worm {
        /// Angle along the spiral.
        var theta: Float
        /// 0 = apple axis, 1 = skin.
        var radial: Float
        /// +1 or -1: crawl direction along the spiral.
        var direction: Float
        var isCaught = false
        /// Seconds before the next burrow.
        var nextBurrow: Float
        /// Seconds left underground (0 = on the surface).
        var underground: Float = 0
        /// 0 = hidden, 1 = fully out (smooth, for the visuals).
        var visibility: Float = 0
        /// Offset of the radial drift, so the worms do not move in sync.
        var phase: Float
    }

    let settings: Settings
    let shape: AppleShape
    private(set) var worms: [Worm] = []
    private(set) var time: Float = 0
    private var random: SeededRandom

    var caughtCount: Int { worms.filter(\.isCaught).count }
    var isCleared: Bool { worms.allSatisfy(\.isCaught) }

    /// Spiral range where the worms crawl: away from the poles, where the slices are thin.
    var crawlRange: ClosedRange<Float> {
        (2 * .pi * 0.6)...(2 * .pi * (shape.turns - 0.4))
    }

    init(shape: AppleShape, settings: Settings = Settings(), seed: UInt64 = 7) {
        self.shape = shape
        self.settings = settings
        random = SeededRandom(seed: seed)
        reset()
    }

    mutating func reset() {
        time = 0
        let range = crawlRange
        worms = (0..<settings.count).map { index in
            // Spread along the spiral, alternating directions.
            let fraction = (Float(index) + 0.5) / Float(settings.count)
            return Worm(theta: range.lowerBound + (range.upperBound - range.lowerBound) * fraction,
                        radial: 0.6,
                        direction: index.isMultiple(of: 2) ? 1 : -1,
                        nextBurrow: Float.random(in: settings.burrowInterval, using: &random),
                        phase: Float(index) * 2.1)
        }
    }

    mutating func update(deltaTime: Float, opening: Float) {
        guard deltaTime > 0 else { return }
        time += deltaTime
        let isOpen = opening >= settings.minimumOpening
        let speed = settings.crawlSpeed * (1 + settings.speedUpPerCatch * Float(caughtCount))
        let range = crawlRange
        let emergeStep = deltaTime / settings.emergeDuration

        for index in worms.indices where !worms[index].isCaught {
            var worm = worms[index]
            // Crawl, turning back at the ends.
            worm.theta += worm.direction * speed * deltaTime
            if worm.theta > range.upperBound {
                worm.theta = range.upperBound
                worm.direction = -1
            } else if worm.theta < range.lowerBound {
                worm.theta = range.lowerBound
                worm.direction = 1
            }
            worm.radial = 0.6 + 0.2 * sin(time * 0.8 + worm.phase)

            // Burrow every now and then (only while the apple is open: closed, they are all hidden anyway).
            if worm.underground > 0 {
                worm.underground = max(0, worm.underground - deltaTime)
            } else if isOpen {
                worm.nextBurrow -= deltaTime
                if worm.nextBurrow <= 0 {
                    worm.underground = settings.burrowDuration
                    worm.nextBurrow = Float.random(in: settings.burrowInterval, using: &random)
                    // Comes out somewhere else, sometimes the other way round.
                    if Float.random(in: 0...1, using: &random) < 0.5 { worm.direction *= -1 }
                }
            }

            let target: Float = isOpen && worm.underground == 0 ? 1 : 0
            worm.visibility = target > worm.visibility
                ? min(target, worm.visibility + emergeStep) : max(target, worm.visibility - emergeStep)
            worms[index] = worm
        }
    }

    /// Can be caught: on the surface (not burrowing) and mostly out of the flesh.
    func isCatchable(_ index: Int) -> Bool {
        guard worms.indices.contains(index) else { return false }
        let worm = worms[index]
        return !worm.isCaught && worm.underground == 0 && worm.visibility > 0.5
    }

    /// Catches the worm if it is out; returns whether it was caught.
    @discardableResult
    mutating func catchWorm(_ index: Int) -> Bool {
        guard isCatchable(index) else { return false }
        worms[index].isCaught = true
        worms[index].visibility = 0
        return true
    }

    /// Position of a worm on top of its slice (apple space), slightly above the flesh.
    func position(of index: Int, opening: Float) -> SIMD3<Float> {
        let worm = worms[index]
        return shape.point(theta: worm.theta, radial: worm.radial, vertical: 0, surface: .top, opening: opening)
            + SIMD3(0, 0.007, 0)
    }

    /// Heading of a worm around the vertical axis (radians), along its crawl direction.
    func heading(of index: Int) -> Float {
        let worm = worms[index]
        return -worm.theta - (worm.direction > 0 ? .pi / 2 : -.pi / 2)
    }
}

/// Small deterministic random generator (SplitMix64): the same seed gives the same worms, so tests are stable.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
