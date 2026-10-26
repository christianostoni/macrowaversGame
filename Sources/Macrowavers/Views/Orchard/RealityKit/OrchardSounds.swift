import Foundation
import RealityKit

/// The orchard's sound effects. Every frame the `OrchardSystem` hands over the orchard: a sound plays when the view
/// model's state changes (a peel torn, a worm caught, the brew starting...), from the thing that makes it
/// (spatial audio). Files missing from the bundle stay silent.
@MainActor
final class OrchardSounds {
    enum Sound: String, CaseIterable {
        case appleOpen = "AppleOpen"
        /// Loops while the worms crawl out of the open apple.
        case wormCrawl = "WormCrawl"
        case wormSquish = "WormSquish"
        /// The pomegranate bursting open, its seeds spilling out (and, for now, the orange splitting open).
        case pomegranateBurst = "PomegranateBurst"
        case bananaPeel = "BananaPeel"
        case pineappleChop = "PineappleChop"
        /// The ingredient (a glowing orb) rising out of its fruit.
        case ingredientRelease = "IngredientRelease"
        case elixirMix = "ElixirMix"
        case elixirBrewed = "ElixirBrewed"

        /// Level of each sound (dB): the worms are tiny, the brewed elixir is the reward.
        var gain: Audio.Decibel {
            switch self {
            case .wormCrawl: -20
            case .wormSquish, .bananaPeel, .ingredientRelease: -8
            case .elixirBrewed: -2
            default: -6
            }
        }
    }

    /// A strip of the banana's peel tears once pulled this far.
    static let peelTear: Float = 0.15
    /// The orange splits into two halves once pulled this far (`OrangeRig`).
    static let orangeSplit: Float = 0.5

    private var resources: [Sound: AudioFileResource] = [:]
    private var crawl: AudioPlaybackController?
    /// What the last frame saw: the sounds play on changes, only for the same focused fruit.
    private var focusedFruitID: Int?
    private var appleOpening: Float = 0
    private var caughtWorms = 0
    private var pomegranateBurst = false
    private var bananaPeel: [Float] = []
    private var orangeOpening: Float = 0
    private var orangeOpened = false
    private var pineappleChopped = false
    private var orbs: [OrbState] = []
    private var elixirState = ElixirState.gathering

    func load() async {
        for sound in Sound.allCases {
            resources[sound] = await GameAudio.load(sound.rawValue, loops: sound == .wormCrawl)
        }
    }

    func update(_ orchard: OrchardComponent) {
        let model = orchard.viewModel
        let focused = orchard.fruits.first { $0.fruit.id == model.focusedFruitID }?.holder
        if model.focusedFruitID == focusedFruitID, let focused {
            playFruitSounds(model, at: focused)
        }
        updateCrawl(model, at: focused)

        for (id, orb) in model.orbs.enumerated() where orbs.indices.contains(id) && orbs[id] == .sealed && orb == .revealed {
            if let holder = orchard.fruits.first(where: { $0.fruit.id == id })?.holder { play(.ingredientRelease, at: holder) }
        }
        if elixirState != .fusing && model.elixir.state == .fusing { play(.elixirMix, at: orchard.elixir.elixir) }
        if elixirState == .fusing && model.elixir.state == .brewed { play(.elixirBrewed, at: orchard.elixir.elixir) }

        focusedFruitID = model.focusedFruitID
        appleOpening = model.appleOpening
        caughtWorms = model.caughtWorms
        pomegranateBurst = model.pomegranateBurst
        bananaPeel = model.bananaPeel
        orangeOpening = model.orangeOpening
        orangeOpened = model.orangeOpened
        pineappleChopped = model.pineappleChopped
        orbs = model.orbs
        elixirState = model.elixir.state
    }

    private func playFruitSounds(_ model: OrchardViewModel, at fruit: Entity) {
        let minimumOpening = model.wormSettings.minimumOpening
        if appleOpening < minimumOpening && model.appleOpening >= minimumOpening { play(.appleOpen, at: fruit) }
        // One at a time: coming back to a cleared apple counts every worm at once, silently.
        if model.caughtWorms == caughtWorms + 1 { play(.wormSquish, at: fruit) }
        if !pomegranateBurst && model.pomegranateBurst { play(.pomegranateBurst, at: fruit) }
        for (strip, pulled) in model.bananaPeel.enumerated()
        where bananaPeel.indices.contains(strip) && bananaPeel[strip] < Self.peelTear && pulled >= Self.peelTear {
            play(.bananaPeel, at: fruit)
        }
        // Into halves, then into wedges.
        if orangeOpening < Self.orangeSplit && model.orangeOpening >= Self.orangeSplit { play(.pomegranateBurst, at: fruit) }
        if !orangeOpened && model.orangeOpened { play(.pomegranateBurst, at: fruit) }
        if !pineappleChopped && model.pineappleChopped { play(.pineappleChop, at: fruit) }
    }

    /// The worms rustle while they crawl out of the open apple, until the last one is caught.
    private func updateCrawl(_ model: OrchardViewModel, at fruit: Entity?) {
        let isCrawling = model.focusedFruit?.kind == .apple && model.appleOpening >= model.wormSettings.minimumOpening
            && !model.worms.isCleared
        if isCrawling, crawl == nil, let fruit {
            crawl = play(.wormCrawl, at: fruit)
        } else if !isCrawling, let playing = crawl {
            playing.fade(to: -80, duration: 0.3)
            crawl = nil
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                playing.stop()
            }
        }
    }

    @discardableResult
    private func play(_ sound: Sound, at entity: Entity) -> AudioPlaybackController? {
        guard let resource = resources[sound] else { return nil }
        if !entity.components.has(SpatialAudioComponent.self) { entity.components.set(SpatialAudioComponent()) }
        let controller = entity.playAudio(resource)
        controller.gain = sound.gain
        return controller
    }
}
