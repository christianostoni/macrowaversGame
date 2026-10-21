import Foundation
import simd

/// The elixir, from the first ingredient found to the dragon soothed.
enum ElixirState: Equatable {
    /// Ingredients orbit the player, fewer than `Elixir.ingredientCount`.
    case gathering
    /// All the ingredients orbit the player: a snap of the fingers brews the elixir.
    case ready
    /// The cork pops, the ingredients dive into the flask one by one, the cork goes back on.
    case fusing
    /// The elixir glows in its flask in front of the player for a moment.
    case brewed
    /// The flask flies to the dragon's head.
    case flying
    /// Delivered: the flask pours the elixir over the dragon's head and fades; the dragon is soothed and comes to
    /// the player.
    case delivered
}

/// The elixir that soothes the dragon, brewed in a flask. The flask appears in the middle of the orbit in front of
/// the player with the first ingredient found, and wobbles each time another one arrives. Once they are all there
/// a snap of the fingers brews the elixir: the cork pops, the ingredients dive into the neck one by one (each
/// raises the liquid by a third and mixes its colour in), the cork goes back on and the liquid swirls into the blue
/// elixir. Pure state and animation curves, advanced by `OrchardViewModel`; the orbit's shape is `ElixirOrbit`.
struct Elixir: Equatable {
    /// Ingredients needed.
    static let ingredientCount = 3
    /// Seconds from the snap to the elixir brewed (`Timeline`).
    static let fusingDuration: Float = Timeline.swirlEnd
    /// Seconds the elixir floats in front of the player before it flies (they see what they made).
    static let brewedHold: Float = 1.2
    /// Seconds the brewed flask swells and settles back (a soft "pop").
    static let popDuration: Float = 0.45
    /// Seconds an ingredient takes to fly from its fruit into the orbit (the flask wobbles when it arrives).
    static let joinDuration: Float = 1.4
    /// Seconds the flask takes to appear with the first ingredient.
    static let appearDuration: Float = 0.6
    /// Seconds the flask pours the elixir over the dragon's head, then fades.
    static let pourDuration: Float = 1.6

    /// Colours of the ingredients' gems, in the order they join the orbit:
    /// pomegranate red, saffron gold, pistachio green. RGB in 0...1.
    static let ingredientColors: [SIMD3<Float>] = [SIMD3(0.9, 0.18, 0.3), SIMD3(1, 0.72, 0.15), SIMD3(0.35, 0.85, 0.4)]
    /// The brewed elixir's blue.
    static let elixirColor = SIMD3<Float>(0.25, 0.55, 1)

    /// Seconds of the brew, from the snap: the cork pops, the ingredients dive in one by one (each lands, then the
    /// liquid rises), the cork goes back on, the liquid swirls into the elixir's blue.
    enum Timeline {
        static let corkPop: Float = 0.4
        static let firstDive: Float = 0.4
        /// Seconds between two dives (a little longer than a dive: they never overlap).
        static let diveSpacing: Float = 0.77
        static let diveDuration: Float = 0.75
        /// Seconds the liquid takes to rise after an ingredient lands.
        static let rise: Float = 0.35
        static let recorkStart: Float = 2.7
        static let recorkEnd: Float = 3.2
        static let swirlEnd: Float = 3.6
    }

    private(set) var orbitingCount = 0
    private(set) var state = ElixirState.gathering
    /// Seconds since `state` last changed (drives the animations).
    private(set) var stateTime: Float = 0
    /// Seconds since the last ingredient was found (it reaches the orbit `joinDuration` later).
    private(set) var sinceCollected = Float.infinity
    /// Seconds since the first ingredient was found: the flask is there.
    private(set) var flaskTime: Float = 0

    var isComplete: Bool { orbitingCount >= Self.ingredientCount }

    /// Colour of the ingredient in `slot`.
    static func ingredientColor(slot: Int) -> SIMD3<Float> {
        let count = ingredientColors.count
        return ingredientColors[((slot % count) + count) % count]
    }

    /// An ingredient joins the orbit; returns the slot it takes, or nil when the orbit takes no more.
    mutating func collect() -> Int? {
        guard state == .gathering, !isComplete else { return nil }
        orbitingCount += 1
        sinceCollected = 0
        if isComplete { enter(.ready) }
        return orbitingCount - 1
    }

    /// The snap: the brew starts. Only with every ingredient in orbit.
    @discardableResult
    mutating func brew() -> Bool {
        guard state == .ready else { return false }
        enter(.fusing)
        return true
    }

    /// Advances the animations. The elixir leaves for the dragon only when `canFly` (the dragon is still on the
    /// island): otherwise it keeps floating in front of the player.
    mutating func update(deltaTime: Float, canFly: Bool) {
        stateTime += deltaTime
        sinceCollected += deltaTime
        if orbitingCount > 0 { flaskTime += deltaTime }
        switch state {
        case .fusing where stateTime >= Self.fusingDuration:
            enter(.brewed)
        case .brewed where stateTime >= Self.brewedHold && canFly:
            enter(.flying)
        default:
            break
        }
    }

    /// The elixir reached the dragon.
    mutating func delivered() {
        guard state == .flying else { return }
        enter(.delivered)
    }

    // MARK: - Animation curves

    /// Seconds since the snap, while brewing; 0 before, the whole brew after.
    private var brewTime: Float {
        switch state {
        case .gathering, .ready: 0
        case .fusing: stateTime
        case .brewed, .flying, .delivered: Self.fusingDuration
        }
    }

    /// How far the brew is (0 = the snap, 1 = brewed).
    var fusionProgress: Float {
        min(brewTime / Self.fusingDuration, 1)
    }

    /// How far the ingredient in `slot` has dived (0 = still in orbit, 1 = in the flask).
    func diveProgress(slot: Int) -> Float {
        let start = Timeline.firstDive + Float(slot) * Timeline.diveSpacing
        return min(max((brewTime - start) / Timeline.diveDuration, 0), 1)
    }

    /// Ingredients already in the flask.
    var landedCount: Int {
        (0..<Self.ingredientCount).filter { diveProgress(slot: $0) >= 1 }.count
    }

    /// Size of an orbiting ingredient (1 = full size): it shrinks into the neck at the end of its dive.
    func ingredientScale(slot: Int) -> Float {
        1 - Self.smoothstep(from: 0.55, to: 1, diveProgress(slot: slot))
    }

    /// Seconds since the ingredient in `slot` landed in the liquid; nil before.
    private func sinceLanding(slot: Int) -> Float? {
        let landing = Timeline.firstDive + Float(slot) * Timeline.diveSpacing + Timeline.diveDuration
        return state == .gathering || state == .ready || brewTime < landing ? nil : brewTime - landing
    }

    /// Share of each ingredient in the liquid (0...1 each, 1/3 of the flask each once its rise is over).
    private func shares() -> [Float] {
        (0..<Self.ingredientCount).map { slot in
            guard let since = sinceLanding(slot: slot) else { return 0 }
            return Self.smoothstep(from: 0, to: Timeline.rise, since)
        }
    }

    /// Level of the liquid (0 = empty, 1 = the flask's full level). It drains while it is poured.
    var fillLevel: Float {
        let level = shares().reduce(0, +) / Float(Self.ingredientCount)
        return state == .delivered ? level * (1 - Self.smoothstep(from: 0.45, to: 1.2, stateTime)) : level
    }

    /// Colour of the liquid: the ingredients mixed by their share, swirling into the elixir's blue once the cork
    /// is back on.
    var liquidColor: SIMD3<Float> {
        let shares = shares()
        let total = shares.reduce(0, +)
        let mixed = total > 0
            ? zip(shares, Self.ingredientColors).map { $0 * $1 }.reduce(SIMD3<Float>(), +) / total
            : Self.ingredientColors[0]
        let swirl = Self.smoothstep(from: Timeline.recorkEnd, to: Timeline.swirlEnd, brewTime)
        return simd_mix(mixed, Self.elixirColor, SIMD3(repeating: swirl))
    }

    /// How brightly the liquid glows (0...1): softly while mixing, fully as the elixir.
    var liquidGlow: Float {
        0.35 + 0.65 * Self.smoothstep(from: Timeline.recorkEnd, to: Timeline.swirlEnd, brewTime)
    }

    /// How far the cork is out of the neck (0 = in, 1 = popped above it, overshooting a little as it pops).
    var corkOut: Float {
        switch state {
        case .gathering, .ready, .brewed, .flying:
            return 0
        case .fusing:
            if stateTime < Timeline.recorkStart { return Self.easeOutBack(stateTime / Timeline.corkPop) }
            return 1 - Self.smoothstep(from: Timeline.recorkStart, to: Timeline.recorkEnd, stateTime)
        case .delivered:
            return Self.easeOutBack(stateTime / Timeline.corkPop)
        }
    }

    /// The liquid sloshing (radians of tilt, damped): when an ingredient reaches the orbit and when one lands.
    var slosh: Float {
        var angle: Float = 0
        let arrival = sinceCollected - Self.joinDuration
        if arrival >= 0, arrival.isFinite { angle += Self.dampedWave(arrival, amplitude: 0.12) }
        for slot in 0..<Self.ingredientCount {
            if let since = sinceLanding(slot: slot) { angle += Self.dampedWave(since, amplitude: 0.2) }
        }
        return angle
    }

    /// The flask wobbling as a whole (radians of tilt, damped) when an ingredient reaches the orbit.
    var wobble: Float {
        let arrival = sinceCollected - Self.joinDuration
        guard arrival >= 0, arrival.isFinite else { return 0 }
        return Self.dampedWave(arrival, amplitude: 0.1)
    }

    /// Glow of the glass in the colour of the ingredient that just reached the orbit (0...1, fading).
    var arrivalGlow: Float {
        let arrival = sinceCollected - Self.joinDuration
        guard arrival >= 0, arrival.isFinite, state == .gathering || state == .ready else { return 0 }
        return exp(-arrival / 0.35)
    }

    /// Size of the flask (1 = full size): it appears with the first ingredient, pops a little when the elixir is
    /// brewed and fades once it has poured the elixir.
    var displayScale: Float {
        let presence = Self.smootherstep(flaskTime / Self.appearDuration)
        switch state {
        case .gathering, .ready, .fusing, .flying:
            return presence
        case .brewed:
            return presence * (1 + 0.08 * sin(.pi * min(stateTime / Self.popDuration, 1)))
        case .delivered:
            return presence * (1 - Self.smoothstep(from: Self.pourDuration - 0.35, to: Self.pourDuration, stateTime))
        }
    }

    /// How far the flask is tipped over the dragon's head (0 = upright, 1 = pouring).
    var pourTilt: Float {
        state == .delivered ? Self.smoothstep(from: 0.15, to: 0.6, stateTime) : 0
    }

    /// The elixir streams out of the neck.
    var isPouring: Bool {
        state == .delivered && stateTime >= 0.45 && stateTime < 1.25
    }

    /// The flask has poured the elixir and faded: nothing left to draw.
    var isFinished: Bool {
        state == .delivered && stateTime >= Self.pourDuration
    }

    /// A decaying wobble: `amplitude · e^(−t / 0.45) · sin(2π · 2.2 t)`.
    static func dampedWave(_ time: Float, amplitude: Float) -> Float {
        amplitude * exp(-time / 0.45) * sin(2 * .pi * 2.2 * time)
    }

    /// 0 → 1 with zero speed and acceleration at both ends (Perlin): no visible start or stop.
    static func smootherstep(_ value: Float) -> Float {
        let x = min(max(value, 0), 1)
        return x * x * x * (x * (6 * x - 15) + 10)
    }

    static func smoothstep(from start: Float, to end: Float, _ value: Float) -> Float {
        let x = min(max((value - start) / (end - start), 0), 1)
        return x * x * (3 - 2 * x)
    }

    /// 0 → 1 overshooting by ~10 % before settling: a soft "pop".
    static func easeOutBack(_ value: Float) -> Float {
        let overshoot: Float = 1.70158
        let x = min(max(value, 0), 1) - 1
        return 1 + (overshoot + 1) * x * x * x + overshoot * x * x
    }

    private mutating func enter(_ state: ElixirState) {
        self.state = state
        stateTime = 0
    }
}
