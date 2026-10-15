import Foundation
import Observation
import simd

enum FruitKind: Equatable {
    case apple
    case pomegranate
    case banana
    case pineapple
}

/// A fruit hanging on the island's tree.
struct Fruit: Identifiable, Equatable {
    let id: Int
    let kind: FruitKind
}

/// The glowing orb sealed inside every fruit.
enum OrbState: Equatable {
    /// Still inside its fruit.
    case sealed
    /// The fruit is open: the orb floats above it. Drag it into the kalash.
    case revealed
    /// In the player's hand, on its way to the kalash.
    case held
    /// In the kalash, at this slot.
    case stored(slot: Int)
    /// Fused into the blue spell.
    case spent

    /// The orb has left its fruit for good.
    var isTaken: Bool {
        switch self {
        case .sealed, .revealed, .held: false
        case .stored, .spent: true
        }
    }
}

/// View model of the tree's fruit: the player picks a fruit, it comes close (zoom-in), they open it and free its
/// glowing orb, then drag the orb into the kalash. Three orbs and a twist of the fingers make the blue spell,
/// which flies to the dragon. Does not know RealityKit or SwiftUI. The immersive view connects it to the dragon
/// (`UntangleViewModel`).
///
/// Every fruit holds one orb, so no choice is wrong: an apple opens by its stem and its worms guard the orb, a
/// pomegranate is pulled apart with two hands, a banana is peeled strip by strip, a pineapple is chopped.
@MainActor
@Observable
final class OrchardViewModel {
    // MARK: - State for the views

    let fruits: [Fruit]
    /// Fruit brought close to the player (nil = all on the tree).
    private(set) var focusedFruitID: Int?
    /// 0 = closed, 1 = fully open (pulled up by the stem).
    private(set) var appleOpening: Float = 0
    private(set) var caughtWorms = 0
    /// 0 = closed, 1 = fully open (pulled apart with two hands).
    private(set) var pomegranateOpening: Float = 0
    /// The pomegranate's seeds have burst out.
    private(set) var pomegranateBurst = false
    /// How far each strip of the banana's peel is pulled down (0 = closed, 1 = hanging fully open).
    private(set) var bananaPeel = Array(repeating: Float(0), count: OrchardViewModel.bananaStrips)
    private(set) var pineappleChopped = false
    /// One orb per fruit, indexed by the fruit's id.
    private(set) var orbs: [OrbState]
    private(set) var kalash = Kalash()
    /// The dragon still circles the tree: set by the immersive view. The spell flies to it only then, and the
    /// kalash takes the pinch only then (later its colliders would steal the grabs on the dragon's knot).
    var isDragonOnIsland = true
    /// The player's hands are tracked: the twist can cast the spell (a tap on the full kalash always can).
    var isHandTrackingAvailable = false
    /// How far the player's twist at the full kalash is (0…1), for the kalash's label. Set by the `OrchardSystem`.
    var twistProgress: Float = 0

    // MARK: - Model

    let appleShape = AppleShape()
    @ObservationIgnored private(set) var worms: WormSwarm
    @ObservationIgnored let wormSettings: WormSwarm.Settings
    /// Seconds since each orb was revealed (drives the rising animation).
    @ObservationIgnored private(set) var orbRevealTimes: [Float]
    @ObservationIgnored private var wormSeed: UInt64 = 1

    /// Opening at which the pomegranate's seeds burst out.
    static let burstOpening: Float = 0.95
    static let bananaStrips = 4
    /// A strip pulled past this counts as peeled; every strip peeled frees the orb.
    static let peeledStrip: Float = 0.8

    init(apples: Int = 3, pomegranates: Int = 1, bananas: Int = 1, pineapples: Int = 1,
         wormSettings: WormSwarm.Settings = WormSwarm.Settings()) {
        let kinds = Array(repeating: FruitKind.apple, count: apples)
            + Array(repeating: .pomegranate, count: pomegranates)
            + Array(repeating: .banana, count: bananas)
            + Array(repeating: .pineapple, count: pineapples)
        fruits = kinds.enumerated().map { Fruit(id: $0.offset, kind: $0.element) }
        orbs = Array(repeating: .sealed, count: kinds.count)
        orbRevealTimes = Array(repeating: 0, count: kinds.count)
        self.wormSettings = wormSettings
        worms = WormSwarm(shape: appleShape, settings: wormSettings)
    }

    var focusedFruit: Fruit? { fruits.first { $0.id == focusedFruitID } }

    /// The focused fruit's orb has already been taken: the "wrong fruit". It never leaves by itself: the player
    /// sends it back to the tree.
    var isFocusedFruitEmpty: Bool {
        guard let id = focusedFruitID else { return false }
        return orbs[id].isTaken
    }

    /// The player has looked inside the focused fruit.
    var isFocusedFruitExplored: Bool {
        switch focusedFruit?.kind {
        case .apple: appleOpening >= wormSettings.minimumOpening
        case .pomegranate: pomegranateBurst
        case .banana: isBananaPeeled
        case .pineapple: pineappleChopped
        case nil: false
        }
    }

    var wormCount: Int { wormSettings.count }
    var isBananaPeeled: Bool { bananaPeel.allSatisfy { $0 >= Self.peeledStrip } }
    /// The orb of the focused fruit, if there is a focused fruit.
    var focusedOrb: OrbState? { focusedFruitID.map { orbs[$0] } }

    // MARK: - Player actions

    /// Brings a fruit close to the player. Only one at a time, and not while the spell is flying.
    @discardableResult
    func focus(fruit id: Int) -> Bool {
        guard focusedFruitID == nil, kalash.spell != .flying, let fruit = fruits.first(where: { $0.id == id }) else {
            return false
        }
        focusedFruitID = id
        closeAll()
        guard fruit.kind == .apple else { return true }

        if orbs[id] == .revealed {
            // Coming back to an apple that already freed its orb: no worms left.
            caughtWorms = wormCount
            return true
        }
        wormSeed &+= 1
        worms = WormSwarm(shape: appleShape, settings: wormSettings, seed: wormSeed)
        caughtWorms = 0
        return true
    }

    /// Puts the fruit back on the tree. A freed orb waits above its fruit for the next visit.
    func back() {
        guard let id = focusedFruitID else { return }
        if orbs[id] == .held { orbs[id] = .revealed }
        focusedFruitID = nil
        closeAll()
    }

    /// Closes the focused fruit again (worms and seeds back inside).
    func restartFruit() {
        guard let fruit = focusedFruit else { return }
        closeAll()
        if fruit.kind == .apple && orbs[fruit.id] == .sealed {
            worms.reset()
            caughtWorms = 0
        }
    }

    func setAppleOpening(_ value: Float) {
        guard focusedFruit?.kind == .apple else { return }
        let opening = min(max(value, 0), 1)
        if opening != appleOpening { appleOpening = opening }
    }

    /// Taps a worm; returns whether it was caught (it may be underground).
    @discardableResult
    func catchWorm(_ index: Int) -> Bool {
        guard focusedFruit?.kind == .apple, appleOpening >= wormSettings.minimumOpening,
              worms.catchWorm(index) else { return false }
        caughtWorms = worms.caughtCount
        if worms.isCleared { revealFocusedOrb() }
        return true
    }

    func setPomegranateOpening(_ value: Float) {
        guard focusedFruit?.kind == .pomegranate else { return }
        let opening = min(max(value, 0), 1)
        if opening != pomegranateOpening { pomegranateOpening = opening }
        if opening >= Self.burstOpening && !pomegranateBurst {
            pomegranateBurst = true
            revealFocusedOrb()
        }
    }

    /// Pulls one strip of the banana's peel (0 = closed, 1 = hanging fully open).
    func setBananaPeel(strip: Int, progress: Float) {
        guard focusedFruit?.kind == .banana, bananaPeel.indices.contains(strip) else { return }
        let progress = min(max(progress, 0), 1)
        if progress != bananaPeel[strip] { bananaPeel[strip] = progress }
        if isBananaPeeled { revealFocusedOrb() }
    }

    /// Chops the pineapple in two (a hand coming down through it, or a tap).
    func chopPineapple() {
        guard focusedFruit?.kind == .pineapple, !pineappleChopped else { return }
        pineappleChopped = true
        revealFocusedOrb()
    }

    /// Everything back on the tree, every orb back in its fruit, the kalash empty.
    func reset() {
        focusedFruitID = nil
        closeAll()
        caughtWorms = 0
        orbs = Array(repeating: .sealed, count: fruits.count)
        orbRevealTimes = Array(repeating: 0, count: fruits.count)
        kalash = Kalash()
        worms.reset()
    }

    // MARK: - Frame update

    /// Called every frame by the `OrchardSystem`.
    func update(deltaTime: Float) {
        if focusedFruit?.kind == .apple {
            worms.update(deltaTime: deltaTime, opening: appleOpening)
        }
        for index in orbs.indices where orbs[index] == .revealed {
            orbRevealTimes[index] += deltaTime
        }
        let before = kalash.spell
        kalash.update(deltaTime: deltaTime, canFly: isDragonOnIsland)
        if before == .forming && kalash.spell == .formed {
            // The orbs have fused: only the blue spell is left.
            for index in orbs.indices where orbs[index].isTaken { orbs[index] = .spent }
        }
        if before != .flying && kalash.spell == .flying {
            // The player follows the spell to the dragon: the fruit in front of them goes back.
            back()
        }
    }

    // MARK: - Private

    private func closeAll() {
        appleOpening = 0
        pomegranateOpening = 0
        pomegranateBurst = false
        bananaPeel = Array(repeating: 0, count: Self.bananaStrips)
        pineappleChopped = false
    }

    private func revealFocusedOrb() {
        guard let id = focusedFruitID, orbs[id] == .sealed else { return }
        orbs[id] = .revealed
        orbRevealTimes[id] = 0
    }
}

// MARK: - Orbs and the kalash

extension OrchardViewModel {
    /// Pinches the orb floating above the focused fruit. Returns whether it is now in the hand.
    @discardableResult
    func grabOrb(fruit id: Int) -> Bool {
        guard id == focusedFruitID, orbs.indices.contains(id), orbs[id] == .revealed || orbs[id] == .held else {
            return false
        }
        orbs[id] = .held
        return true
    }

    /// Lets go of the orb. Dropped into the kalash (and the kalash still takes orbs) it stays there and the fruit
    /// goes back to the tree; anywhere else it floats back above its fruit. Returns whether it went in.
    @discardableResult
    func releaseOrb(fruit id: Int, intoKalash: Bool) -> Bool {
        guard orbs.indices.contains(id), orbs[id] == .held else { return false }
        guard intoKalash, let slot = kalash.store() else {
            orbs[id] = .revealed
            return false
        }
        orbs[id] = .stored(slot: slot)
        if id == focusedFruitID { back() }
        return true
    }

    /// The twist while looking at the full kalash: the orbs start fusing into the blue spell.
    @discardableResult
    func castSpell() -> Bool {
        kalash.cast()
    }

    /// The blue spell reached the dragon.
    func spellDelivered() {
        kalash.delivered()
    }
}
