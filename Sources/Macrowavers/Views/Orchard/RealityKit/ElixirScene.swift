import RealityKit
import simd
import UIKit

/// The elixir drawn in RealityKit: the glowing blue elixir the ingredients fuse into, the flash of their fusion
/// and the anchor of its label (under the orbit, in front of the player). Both live under the orchard's root, in
/// scene space; the orbit itself is `ElixirOrbit`, kept by the `OrchardComponent`.
@MainActor
final class ElixirRig {
    static let elixirName = "Elixir"
    static let hintAnchorName = "ElixirHintAnchor"

    let elixir: Entity
    /// The elixir's label hangs from it (`ElixirPanelView`).
    let hintAnchor = Entity()
    /// The flash of the fusion: a burst of sparks from where the ingredients meet.
    private let burst: Entity

    init() {
        elixir = Self.makeElixir()
        elixir.isEnabled = false
        burst = Self.makeBurst()
        elixir.addChild(burst)
        hintAnchor.name = Self.hintAnchorName
    }

    /// Sparks bursting out of the elixir the moment it is brewed.
    func flash() {
        guard var emitter = burst.components[ParticleEmitterComponent.self] else { return }
        emitter.burst()
        burst.components.set(emitter)
    }

    // MARK: - Drawing

    /// The elixir: a glowing blue orb with a halo and sparkles (placeholder until the design team's asset).
    private static func makeElixir() -> Entity {
        let elixir = Entity()
        elixir.name = elixirName
        var core = PhysicallyBasedMaterial()
        core.baseColor = .init(tint: UIColor(red: 0.3, green: 0.6, blue: 1, alpha: 1))
        core.emissiveColor = .init(color: UIColor(red: 0.25, green: 0.55, blue: 1, alpha: 1))
        core.emissiveIntensity = 3
        core.roughness = 0.15
        elixir.addChild(ModelEntity(mesh: .generateSphere(radius: 0.035), materials: [core]))
        var halo = UnlitMaterial(color: UIColor(red: 0.45, green: 0.75, blue: 1, alpha: 1))
        halo.blending = .transparent(opacity: .init(floatLiteral: 0.25))
        elixir.addChild(ModelEntity(mesh: .generateSphere(radius: 0.055), materials: [halo]))

        var sparkles = ParticleEmitterComponent()
        sparkles.emitterShape = .sphere
        sparkles.emitterShapeSize = SIMD3(repeating: 0.04)
        sparkles.mainEmitter.birthRate = 40
        sparkles.mainEmitter.lifeSpan = 0.8
        sparkles.mainEmitter.size = 0.003
        sparkles.speed = 0.04
        sparkles.mainEmitter.color = .constant(.single(UIColor(red: 0.6, green: 0.85, blue: 1, alpha: 1)))
        elixir.components.set(sparkles)
        return elixir
    }

    private static func makeBurst() -> Entity {
        let entity = Entity()
        var burst = ParticleEmitterComponent()
        burst.emitterShape = .sphere
        burst.emitterShapeSize = SIMD3(repeating: 0.02)
        burst.birthDirection = .normal
        burst.speed = 0.35
        burst.speedVariation = 0.15
        burst.isEmitting = false
        burst.burstCount = 160
        burst.mainEmitter.lifeSpan = 0.9
        burst.mainEmitter.size = 0.004
        burst.mainEmitter.color = .evolving(start: .single(UIColor(red: 0.85, green: 0.95, blue: 1, alpha: 1)),
                                            end: .single(UIColor(red: 0.2, green: 0.45, blue: 1, alpha: 1)))
        entity.components.set(burst)
        return entity
    }
}

// MARK: - System

extension OrchardSystem {
    /// The orbit follows the player (lazily) and turns; faster while the ingredients fuse; above the fruit while
    /// one is in front of the player.
    @MainActor
    static func updateOrbit(_ orchard: inout OrchardComponent, deltaTime: Float) {
        let viewModel = orchard.viewModel
        let elixir = viewModel.elixir
        let spin = elixir.state == .fusing
            ? 1 + orchard.orbit.settings.fusionSpin * Elixir.smootherstep(elixir.fusionProgress)
            : 1
        let viewer = orchard.viewer.viewerPose()
        orchard.orbit.follow(eyes: viewer.position, forward: viewer.forward, deltaTime: deltaTime, spin: spin,
                             makesRoom: viewModel.focusedFruitID != nil)
        orchard.elixir.hintAnchor.position = orchard.orbit.hintPoint
    }

    /// Every ingredient in orbit and a snap of the fingers: the elixir is brewed (with hand tracking; a tap on an
    /// ingredient works anyway).
    @MainActor
    static func detectSnap(_ orchard: inout OrchardComponent) {
        let viewModel = orchard.viewModel
        defer {
            let isLoaded = orchard.snap.isLoaded
            if viewModel.isSnapLoaded != isLoaded { viewModel.isSnapLoaded = isLoaded }
            let debug = snapDebug(orchard.snap)
            if viewModel.snapDebug != debug { viewModel.snapDebug = debug }
        }
        guard viewModel.elixir.state == .ready else {
            orchard.snap.reset()
            return
        }
        orchard.snap.beginFrame()
        var snapped = false
        // Both hands every frame (no early exit): each keeps its own state.
        for sample in orchard.hands.samples.values where orchard.snap.process(sample) {
            snapped = true
        }
        if snapped { viewModel.brewElixir() }
    }

    /// "pad 2.5 cm · last +3.0/1.0 cm 0.8 m/s ✗", rounded to half centimetres (changes now and then, not every frame).
    private static func snapDebug(_ snap: SnapDetector) -> String {
        func centimetres(_ metres: Float) -> String {
            ((metres * 200).rounded() / 2).formatted(.number.precision(.fractionLength(1)))
        }
        let contact = snap.closestContact.map { "pad \(centimetres($0)) cm" } ?? "no hands"
        guard let attempt = snap.lastAttempt else { return contact }
        let speed = ((attempt.speed * 2).rounded() / 2).formatted(.number.precision(.fractionLength(1)))
        return "\(contact) · last +\(centimetres(attempt.separation))/\(centimetres(attempt.curl)) cm "
            + "\(speed) m/s \(attempt.isSnap ? "✓" : "✗")"
    }

    /// Draws the elixir: growing out of the converging ingredients, popping with a flash, floating in front of
    /// the player, then flying in an arc to the dragon's head.
    @MainActor
    static func updateElixir(_ orchard: inout OrchardComponent, root: Entity, deltaTime: Float) {
        let rig = orchard.elixir
        let state = orchard.viewModel.elixir
        let target = orchard.deliveryTarget.position(relativeTo: root)
        if state.state != orchard.drawnElixirState {
            switch state.state {
            case .brewed: rig.flash()
            case .flying: orchard.flight = ElixirFlight(from: rig.elixir.position, to: target)
            case .gathering, .ready, .fusing, .delivered: orchard.flight = nil
            }
            orchard.drawnElixirState = state.state
        }
        let pulse = 1 + 0.1 * sin(orchard.time * 5)
        switch state.state {
        case .gathering, .ready, .delivered:
            rig.elixir.isEnabled = false
        case .fusing, .brewed:
            attach(rig.elixir, to: root, preservingWorldTransform: false)
            rig.elixir.isEnabled = true
            let bob: Float = state.state == .brewed ? 0.012 * sin(orchard.time * 2) : 0
            rig.elixir.position = orchard.orbit.center + SIMD3(0, bob, 0)
            rig.elixir.setScale(SIMD3(repeating: max(state.displayScale, 0.001) * (state.state == .brewed ? pulse : 1)),
                                relativeTo: nil)
        case .flying:
            guard var flight = orchard.flight else { return }
            flight.advance(deltaTime: deltaTime)
            orchard.flight = flight
            if flight.isArrived {
                rig.elixir.isEnabled = false
                orchard.viewModel.elixirDelivered()
            } else {
                rig.elixir.position = flight.position(towards: target)
                rig.elixir.setScale(SIMD3(repeating: pulse), relativeTo: nil)
            }
        }
    }
}
