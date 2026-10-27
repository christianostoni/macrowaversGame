import Foundation
import Observation
import simd

enum FruitKind: Equatable {
    case apple
    case pomegranate
    case banana
    case orange
    case pineapple
}

/// A fruit hanging on the island's tree.
struct Fruit: Identifiable, Equatable {
    let id: Int
    let kind: FruitKind
}

/// The glowing orb sealed inside every fruit: an ingredient of the elixir.
enum OrbState: Equatable {
    /// Still inside its fruit.
    case sealed
    /// The fruit is open: the orb rises out of it, then joins the orbit at the player's side by itself.
    case revealed
    /// Orbiting the player, at this slot of the orbit.
    case orbiting(slot: Int)
    /// In the flask: brewed into the elixir.
    case spent

    /// The orb has left its fruit for good.
    var isTaken: Bool {
        switch self {
        case .sealed, .revealed: false
        case .orbiting, .spent: true
        }
    }
}

/// View model of the tree's fruit: the player picks a fruit, it comes close (zoom-in), they open it and free its
/// glowing orb, an ingredient, which rises and joins an orbit at the player's side. Three ingredients and a snap of
/// the fingers brew the elixir, which flies to the dragon. Does not know RealityKit or SwiftUI. The immersive view
/// connects it to the dragon (`UntangleViewModel`).
///
/// Every fruit holds one orb, so no choice is wrong: an apple opens by its stem and its worms guard the orb, a
/// pomegranate is pulled apart with two hands, a banana is peeled strip by strip, an orange is pulled apart into wedges,
/// a pineapple is chopped.
@MainActor
@Observable
final class OrchardViewModel {
    // MARK: - State for the views

    let fruits: [Fruit]
    /// Fruit brought close to the player (nil = all on the tree).
    private(set) var focusedFruitID: Int?
    /// 0 = closed, 1 = fully open (pulled up by the stem). Changes every frame while the stem is pulled: not
    /// observed (the fruit panel would be redrawn every frame); views read `isAppleOpen`.
    @ObservationIgnored private(set) var appleOpening: Float = 0 {
        didSet {
            let isOpen = appleOpening >= wormSettings.minimumOpening
            if isOpen != isAppleOpen { isAppleOpen = isOpen }
        }
    }
    /// The apple is open enough to see (and catch) its worms.
    private(set) var isAppleOpen = false
    private(set) var caughtWorms = 0
    /// 0 = closed, 1 = fully open (pulled apart with two hands).
    private(set) var pomegranateOpening: Float = 0
    /// The pomegranate's seeds have burst out.
    private(set) var pomegranateBurst = false
    /// How far each strip of the banana's peel is pulled down (0 = closed, 1 = hanging fully open).
    private(set) var bananaPeel = Array(repeating: Float(0), count: OrchardViewModel.bananaStrips)
    /// 0 = whole, 0.5 = two halves, 1 = eight wedges (pulled apart with two hands).
    private(set) var orangeOpening: Float = 0
    /// The orange has fanned out into its wedges.
    private(set) var orangeOpened = false
    private(set) var pineappleChopped = false
    /// One orb per fruit, indexed by the fruit's id.
    private(set) var orbs: [OrbState]
    /// Advanced every frame (its animation clocks): not observed, or every view reading it would be redrawn every
    /// frame. The systems read it; views read `elixirState` and `orbitingCount`, set only when they change.
    @ObservationIgnored private(set) var elixir = Elixir() {
        didSet {
            if elixir.state != elixirState { elixirState = elixir.state }
            if elixir.orbitingCount != orbitingCount { orbitingCount = elixir.orbitingCount }
        }
    }
    private(set) var elixirState = ElixirState.gathering
    /// Ingredients in orbit.
    private(set) var orbitingCount = 0
    /// The dragon still circles the tree: set by the immersive view. The elixir flies to it only then, and the
    /// orbiting ingredients take the pinch only then (later they would steal the grabs on the dragon's knot).
    var isDragonOnIsland = true
    /// The player's hands are tracked: the snap can brew the elixir (a tap on an ingredient always can).
    var isHandTrackingAvailable = false

    // MARK: - Model

    let appleShape = AppleShape()
    @ObservationIgnored private(set) var worms: WormSwarm
    @ObservationIgnored let wormSettings: WormSwarm.Settings
    /// Seconds since each orb was revealed (drives the rising animation, then sends it into orbit).
    @ObservationIgnored private(set) var orbRevealTimes: [Float]
    @ObservationIgnored private var wormSeed: UInt64 = 1

    /// Opening at which the pomegranate's seeds burst out.
    static let burstOpening: Float = 0.95
    static let bananaStrips = 4
    /// A strip pulled past this counts as peeled; every strip peeled frees the orb.
    static let peeledStrip: Float = 0.8
    /// Opening at which the orange's wedges count as open and free the orb.
    static let wedgesOpening: Float = 0.9
    /// Seconds a freed orb takes to rise out of its fruit (it can be tapped into orbit from then on) ...
    static let orbRiseDuration: Float = 1.2
    /// ... and how long it then floats there before joining the orbit by itself (the player sees what they found).
    static let orbOrbitDelay: Float = 0.6

    init(apples: Int = 3, pomegranates: Int = 1, bananas: Int = 1, oranges: Int = 1, pineapples: Int = 1,
         wormSettings: WormSwarm.Settings = WormSwarm.Settings()) {
        let kinds = Array(repeating: FruitKind.apple, count: apples)
            + Array(repeating: .pomegranate, count: pomegranates)
            + Array(repeating: .banana, count: bananas)
            + Array(repeating: .orange, count: oranges)
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
        case .apple: isAppleOpen
        case .pomegranate: pomegranateBurst
        case .banana: isBananaPeeled
        case .orange: orangeOpened
        case .pineapple: pineappleChopped
        case nil: false
        }
    }

    var wormCount: Int { wormSettings.count }
    var isBananaPeeled: Bool { bananaPeel.allSatisfy { $0 >= Self.peeledStrip } }
    /// The orb of the focused fruit, if there is a focused fruit.
    var focusedOrb: OrbState? { focusedFruitID.map { orbs[$0] } }

    // MARK: - Player actions

    /// Brings a fruit close to the player. Only one at a time, and not while the elixir is flying.
    @discardableResult
    func focus(fruit id: Int) -> Bool {
        guard focusedFruitID == nil, elixir.state != .flying, let fruit = fruits.first(where: { $0.id == id }) else {
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

    /// Puts the fruit back on the tree. A freed orb still joins the orbit from there.
    func back() {
        guard focusedFruitID != nil else { return }
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
        guard focusedFruit?.kind == .apple, isAppleOpen, worms.catchWorm(index) else { return false }
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

    func setOrangeOpening(_ value: Float) {
        guard focusedFruit?.kind == .orange else { return }
        let opening = min(max(value, 0), 1)
        if opening != orangeOpening { orangeOpening = opening }
        if opening >= Self.wedgesOpening && !orangeOpened {
            orangeOpened = true
            revealFocusedOrb()
        }
    }

    /// Chops the pineapple in two (a hand coming down through it, or a tap).
    func chopPineapple() {
        guard focusedFruit?.kind == .pineapple, !pineappleChopped else { return }
        pineappleChopped = true
        revealFocusedOrb()
    }

    /// Everything back on the tree, every orb back in its fruit, no elixir.
    func reset() {
        focusedFruitID = nil
        closeAll()
        caughtWorms = 0
        orbs = Array(repeating: .sealed, count: fruits.count)
        orbRevealTimes = Array(repeating: 0, count: fruits.count)
        elixir = Elixir()
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
            // Found: after rising and floating for a moment it joins the others in orbit.
            if orbRevealTimes[index] >= Self.orbRiseDuration + Self.orbOrbitDelay { sendToOrbit(fruit: index) }
        }
        let before = elixir.state
        elixir.update(deltaTime: deltaTime, canFly: isDragonOnIsland)
        if before == .fusing && elixir.state == .brewed {
            // The ingredients are in the flask: only the elixir is left.
            for index in orbs.indices where orbs[index].isTaken { orbs[index] = .spent }
        }
        if before != .flying && elixir.state == .flying {
            // The player follows the elixir to the dragon: the fruit in front of them goes back.
            back()
        }
    }

    // MARK: - Private

    private func closeAll() {
        appleOpening = 0
        pomegranateOpening = 0
        pomegranateBurst = false
        bananaPeel = Array(repeating: 0, count: Self.bananaStrips)
        orangeOpening = 0
        orangeOpened = false
        pineappleChopped = false
    }

    private func revealFocusedOrb() {
        guard let id = focusedFruitID, orbs[id] == .sealed else { return }
        orbs[id] = .revealed
        orbRevealTimes[id] = 0
    }
}

// MARK: - Ingredients and the elixir

extension OrchardViewModel {
    /// Taps the orb risen out of a fruit: it joins the orbit now instead of waiting. Returns whether it did.
    @discardableResult
    func collectOrb(fruit id: Int) -> Bool {
        guard orbs.indices.contains(id), orbs[id] == .revealed, orbRevealTimes[id] >= Self.orbRiseDuration else {
            return false
        }
        return sendToOrbit(fruit: id)
    }

    /// The snap of the fingers (or a tap on an ingredient) with every ingredient in orbit: they start diving into
    /// the flask. A fruit still in front of the player goes back, out of the way of the brew.
    @discardableResult
    func brewElixir() -> Bool {
        guard elixir.brew() else { return false }
        back()
        return true
    }

    /// The elixir reached the dragon.
    func elixirDelivered() {
        elixir.delivered()
    }

    /// The orb joins the orbit, if the orbit still takes ingredients (otherwise it keeps floating above its fruit).
    /// Its fruit has nothing more to give: it goes back to the tree.
    @discardableResult
    private func sendToOrbit(fruit id: Int) -> Bool {
        guard orbs[id] == .revealed, let slot = elixir.collect() else { return false }
        orbs[id] = .orbiting(slot: slot)
        if id == focusedFruitID { back() }
        return true
    }
}
