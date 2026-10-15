import Foundation

/// The kalash's spell, from the first orb dropped in to the dragon soothed.
enum SpellState: Equatable {
    /// Waiting for orbs (fewer than `Kalash.capacity` inside).
    case gathering
    /// Full: look at the kalash and twist the pinched fingers to cast.
    case ready
    /// The orbs swirl up out of the kalash and fuse.
    case forming
    /// The blue spell floats above the kalash.
    case formed
    /// The blue spell flies to the dragon's head.
    case flying
    /// Delivered: the dragon is soothed and comes to the player.
    case delivered
}

/// The spell container the player carries: the orbs found in the tree's fruit go in, and once full a twist of the
/// fingers turns them into the blue spell that soothes the dragon. Pure state, advanced by `OrchardViewModel`.
struct Kalash: Equatable {
    /// Orbs needed for the spell.
    static let capacity = 3
    /// Seconds the orbs take to fuse into the spell.
    static let formingDuration: Float = 1.5
    /// Seconds the blue spell floats above the kalash before it flies (the player sees what they made).
    static let formedHold: Float = 1.2

    private(set) var storedCount = 0
    private(set) var spell = SpellState.gathering
    /// Seconds since `spell` last changed (drives the animations).
    private(set) var stateTime: Float = 0

    var isFull: Bool { storedCount >= Self.capacity }

    /// Puts an orb in; returns the slot it takes, or nil when the kalash takes no more.
    mutating func store() -> Int? {
        guard spell == .gathering, !isFull else { return nil }
        storedCount += 1
        if isFull { enter(.ready) }
        return storedCount - 1
    }

    /// The twist: the orbs start fusing. Only when the kalash is full.
    @discardableResult
    mutating func cast() -> Bool {
        guard spell == .ready else { return false }
        enter(.forming)
        return true
    }

    /// Advances the animations. The spell leaves for the dragon only when `canFly` (the dragon is still on the
    /// island): otherwise it stays above the kalash.
    mutating func update(deltaTime: Float, canFly: Bool) {
        stateTime += deltaTime
        switch spell {
        case .forming where stateTime >= Self.formingDuration:
            enter(.formed)
        case .formed where stateTime >= Self.formedHold && canFly:
            enter(.flying)
        default:
            break
        }
    }

    /// The spell reached the dragon.
    mutating func delivered() {
        guard spell == .flying else { return }
        enter(.delivered)
    }

    private mutating func enter(_ state: SpellState) {
        spell = state
        stateTime = 0
    }
}
