import Foundation
import Observation
import simd

enum FruitKind: Equatable {
    case apple
    case pomegranate
}

/// A fruit hanging on the island's tree.
struct Fruit: Identifiable, Equatable {
    let id: Int
    let kind: FruitKind
}

/// The one artifact that soothes the dragon.
enum ArtifactState: Equatable {
    /// Not found yet: it waits in the first apple whose worms are all caught.
    case hidden
    /// Inside the apple being inspected, guarded by its worms.
    case guarded
    /// The worms are gone: it rises out of the apple. Tap it to use it.
    case revealed
    /// Flying from the apple to the dragon.
    case flying
    /// Delivered: the dragon is soothed and comes to the player.
    case used
}

/// View model of the tree's fruit: the player picks a fruit, it comes close (zoom-in), they open it and,
/// in an apple, catch the worms to free the artifact, which then flies to the dragon.
/// Does not know RealityKit or SwiftUI. The immersive view connects it to the dragon (`UntangleViewModel`).
///
/// Kept easy on purpose: there is a single artifact and it is always in the **first** apple whose worms are
/// cleared, so no choice is wrong. The pomegranate is a bonus fruit: it opens with two hands and its seeds
/// can be played with, but it never holds the artifact.
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
    private(set) var artifact = ArtifactState.hidden

    // MARK: - Model

    let appleShape = AppleShape()
    @ObservationIgnored private(set) var worms: WormSwarm
    @ObservationIgnored let wormSettings: WormSwarm.Settings
    /// Apple that holds the revealed artifact (so it is still there if the player looks at it again).
    @ObservationIgnored private(set) var artifactFruitID: Int?
    /// Seconds since the artifact was revealed (drives the rising animation).
    @ObservationIgnored private(set) var artifactRevealTime: Float = 0
    @ObservationIgnored private var wormSeed: UInt64 = 1

    /// Opening at which the pomegranate's seeds burst out.
    static let burstOpening: Float = 0.95

    init(apples: Int = 3, pomegranates: Int = 1, wormSettings: WormSwarm.Settings = WormSwarm.Settings()) {
        let kinds = Array(repeating: FruitKind.apple, count: apples) + Array(repeating: .pomegranate, count: pomegranates)
        fruits = kinds.enumerated().map { Fruit(id: $0.offset, kind: $0.element) }
        self.wormSettings = wormSettings
        worms = WormSwarm(shape: appleShape, settings: wormSettings)
    }

    var focusedFruit: Fruit? { fruits.first { $0.id == focusedFruitID } }
    var wormCount: Int { wormSettings.count }
    /// The artifact is out of the fruit (or already used): nothing left to look for.
    var isArtifactFound: Bool { artifact == .revealed || artifact == .flying || artifact == .used }

    // MARK: - Player actions

    /// Brings a fruit close to the player. Only one at a time, and not while the artifact is flying.
    @discardableResult
    func focus(fruit id: Int) -> Bool {
        guard focusedFruitID == nil, artifact != .flying, let fruit = fruits.first(where: { $0.id == id }) else { return false }
        focusedFruitID = id
        appleOpening = 0
        pomegranateOpening = 0
        pomegranateBurst = false
        guard fruit.kind == .apple else { return true }

        if artifactFruitID == id && artifact == .revealed {
            // Coming back to the apple that already freed the artifact: no worms left.
            caughtWorms = wormCount
            return true
        }
        wormSeed &+= 1
        worms = WormSwarm(shape: appleShape, settings: wormSettings, seed: wormSeed)
        caughtWorms = 0
        if artifact == .hidden { artifact = .guarded }
        return true
    }

    /// Puts the fruit back on the tree. An artifact still guarded goes back to waiting for the next apple.
    func back() {
        guard focusedFruitID != nil else { return }
        if artifact == .guarded { artifact = .hidden }
        focusedFruitID = nil
        appleOpening = 0
        pomegranateOpening = 0
        pomegranateBurst = false
    }

    /// Closes the focused fruit again (worms and seeds back inside).
    func restartFruit() {
        guard let fruit = focusedFruit else { return }
        appleOpening = 0
        pomegranateOpening = 0
        pomegranateBurst = false
        if fruit.kind == .apple && artifact == .guarded {
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
        if worms.isCleared && artifact == .guarded {
            artifact = .revealed
            artifactFruitID = focusedFruitID
            artifactRevealTime = 0
        }
        return true
    }

    func setPomegranateOpening(_ value: Float) {
        guard focusedFruit?.kind == .pomegranate else { return }
        let opening = min(max(value, 0), 1)
        if opening != pomegranateOpening { pomegranateOpening = opening }
        if opening >= Self.burstOpening && !pomegranateBurst { pomegranateBurst = true }
    }

    /// Taps the revealed artifact: it flies to the dragon. Returns whether it left.
    @discardableResult
    func useArtifact() -> Bool {
        guard artifact == .revealed, focusedFruitID == artifactFruitID else { return false }
        artifact = .flying
        return true
    }

    /// The artifact reached the dragon: the fruit goes back to the tree.
    func artifactDelivered() {
        guard artifact == .flying else { return }
        artifact = .used
        artifactFruitID = nil
        back()
    }

    /// Everything back on the tree, artifact hidden again.
    func reset() {
        focusedFruitID = nil
        appleOpening = 0
        caughtWorms = 0
        pomegranateOpening = 0
        pomegranateBurst = false
        artifact = .hidden
        artifactFruitID = nil
        artifactRevealTime = 0
        worms.reset()
    }

    // MARK: - Frame update

    /// Called every frame by the `OrchardSystem`.
    func update(deltaTime: Float) {
        if focusedFruit?.kind == .apple {
            worms.update(deltaTime: deltaTime, opening: appleOpening)
        }
        if artifact == .revealed { artifactRevealTime += deltaTime }
    }
}
