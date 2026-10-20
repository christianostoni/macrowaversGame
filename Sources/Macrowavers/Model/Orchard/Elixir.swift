import Foundation

/// The elixir, from the first ingredient found to the dragon soothed.
enum ElixirState: Equatable {
    /// Ingredients orbit the player, fewer than `Elixir.ingredientCount`.
    case gathering
    /// All the ingredients orbit the player: a snap of the fingers brews the elixir.
    case ready
    /// The ingredients spiral in from their orbit and fuse.
    case fusing
    /// The elixir floats in front of the player for a moment.
    case brewed
    /// The elixir flies to the dragon's head.
    case flying
    /// Delivered: the dragon is soothed and comes to the player.
    case delivered
}

/// The elixir that soothes the dragon: every ingredient found in the tree's fruit joins an orbit around the
/// player, and once they are all there a snap of the fingers fuses them into the elixir. Pure state, advanced by
/// `OrchardViewModel`; the orbit's shape is `ElixirOrbit`.
struct Elixir: Equatable {
    /// Ingredients needed.
    static let ingredientCount = 3
    /// Seconds the ingredients take to spiral in and fuse.
    static let fusingDuration: Float = 2.2
    /// Seconds the elixir floats in front of the player before it flies (they see what they made).
    static let brewedHold: Float = 1.2
    /// Seconds the brewed elixir takes to pop to its full size.
    static let popDuration: Float = 0.45

    private(set) var orbitingCount = 0
    private(set) var state = ElixirState.gathering
    /// Seconds since `state` last changed (drives the animations).
    private(set) var stateTime: Float = 0

    var isComplete: Bool { orbitingCount >= Self.ingredientCount }

    /// An ingredient joins the orbit; returns the slot it takes, or nil when the orbit takes no more.
    mutating func collect() -> Int? {
        guard state == .gathering, !isComplete else { return nil }
        orbitingCount += 1
        if isComplete { enter(.ready) }
        return orbitingCount - 1
    }

    /// The snap: the ingredients start fusing. Only with every ingredient in orbit.
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

    /// How far the fusion is (0 = still in orbit, 1 = fused).
    var fusionProgress: Float {
        switch state {
        case .gathering, .ready: 0
        case .fusing: min(stateTime / Self.fusingDuration, 1)
        case .brewed, .flying, .delivered: 1
        }
    }

    /// Size of the elixir drawn (1 = full size): it grows out of the converging ingredients in the last part of
    /// the fusion, then pops to its full size with a small overshoot.
    var displayScale: Float {
        switch state {
        case .gathering, .ready, .delivered:
            0
        case .fusing:
            0.6 * Self.smoothstep(from: 0.55, to: 1, fusionProgress)
        case .brewed:
            0.6 + 0.4 * Self.easeOutBack(min(stateTime / Self.popDuration, 1))
        case .flying:
            1
        }
    }

    /// Size of an orbiting ingredient (1 = full size): it shrinks into the elixir while they fuse.
    var ingredientScale: Float {
        1 - 0.7 * Self.smootherstep(fusionProgress)
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
