import RealityKit
import simd
import UIKit

/// The elixir drawn in RealityKit: the design team's flask (`ElixirFlask.usdz`) in the middle of the orbit, its
/// liquid rising and mixing as the ingredients dive in, its cork popping, bubbles, a glow that lights the player's
/// hands, the flash of the brewed elixir and the elixir poured over the dragon's head; plus the anchor of its label
/// (under the orbit). Everything is read from `Elixir` (the model decides, this only draws). Both entities live under
/// the orchard's root, in scene space; the orbit itself is `ElixirOrbit`, kept by the `OrchardComponent`.
@MainActor
final class ElixirRig {
    static let elixirName = "Elixir"
    static let hintAnchorName = "ElixirHintAnchor"
    static let flaskAssetName = "ElixirFlask"
    /// Size of the flask in the orbit: the asset is real size (~21 cm wide); smaller, it fits in the
    /// orbit (28 cm deep) without touching the ingredients going round it.
    static let flaskScale: Float = 0.7
    /// How far the flask leans over the dragon's head to pour (radians): the neck points down.
    static let pourAngle: Float = 2.2
    /// How far the cork flies out of the neck (m, flask space) and to the side.
    static let corkRise: Float = 0.1
    static let corkSide: Float = 0.04
    /// Height of the flask above the dragon's head while it pours (m).
    static let pourHeight: Float = 0.12

    /// Placed, sized and turned by `OrchardSystem.updateElixir`.
    let elixir: Entity
    /// The elixir's label hangs from it (`ElixirPanelView`).
    let hintAnchor = Entity()
    /// The flask itself, under `elixir`: leans as it wobbles and pours.
    private let flask: Entity
    private let neckTop: Entity
    private let neckBase: Entity
    private let liquid: LiquidPart?
    private let cork: CorkPart?
    private let glass: ModelEntity?
    /// The flash of the brewed elixir: a burst of sparks out of the flask.
    private let burst: Entity
    /// Bubbles rising in the liquid; a burst when an ingredient lands.
    private let bubbles: Entity
    /// The elixir streaming out of the neck over the dragon's head.
    private let stream: Entity
    /// The liquid's glow, lighting what is around the flask.
    private let glow: Entity
    /// Values already applied to the materials and the light (they change only now and then).
    private var appliedLiquid: SIMD4<Float>?
    private var appliedGlass: SIMD4<Float>?

    /// The liquid: scaled along its own vertical axis from its bottom (its origin) to raise its level.
    private struct LiquidPart {
        let entity: Entity
        let model: ModelEntity
        let rest: Transform
        /// Its local axis pointing up in the flask, and a horizontal one to slosh around.
        let upAxis: Int
        let slosh: SIMD3<Float>
    }

    /// The cork: pops along the neck's axis, tumbling.
    private struct CorkPart {
        let entity: Entity
        let rest: Transform
        /// The neck's axis and a side direction, in the cork's parent space.
        let axis: SIMD3<Float>
        let side: SIMD3<Float>
    }

    private init(flask: Entity, model: Entity?) {
        elixir = Entity()
        elixir.name = Self.elixirName
        elixir.isEnabled = false
        self.flask = flask
        elixir.addChild(flask)
        hintAnchor.name = Self.hintAnchorName

        let parts = model.map(Self.parts(of:))
        neckTop = parts?.neckTop ?? Self.marker(at: SIMD3(0, 0.07, 0), in: flask)
        neckBase = parts?.neckBase ?? Self.marker(at: SIMD3(0, 0.04, 0), in: flask)
        liquid = parts.flatMap { Self.liquidPart($0.liquid, flask: flask) }
        cork = parts.flatMap { Self.corkPart($0.cork, neckTop: $0.neckTop, neckBase: $0.neckBase) }
        glass = parts?.glass.flatMap(Self.firstModel(in:))

        burst = Self.makeBurst()
        bubbles = Self.makeBubbles()
        stream = Self.makeStream()
        glow = Entity()
        glow.components.set(PointLightComponent(color: .white, intensity: 0, attenuationRadius: 0.6))
        for effect in [burst, bubbles, glow] { flask.addChild(effect) }
        flask.addChild(stream)
        stream.position = neckTop.position(relativeTo: flask)
        let axis = simd_normalize(neckTop.position(relativeTo: flask) - neckBase.position(relativeTo: flask))
        stream.components[ParticleEmitterComponent.self]?.emissionDirection = axis

        if let glass {
            glass.components.set(ModelSortGroupComponent(group: Self.sortGroup, order: 1))
        }
        if let liquid {
            liquid.model.components.set(ModelSortGroupComponent(group: Self.sortGroup, order: 0))
        }
    }

    /// Loads the flask; without its asset, a glowing orb stands in for it (the brew still plays).
    static func make() async -> ElixirRig {
        let flask = Entity()
        do {
            let model = try await Entity(named: flaskAssetName, in: .main)
            flask.addChild(model)
            return ElixirRig(flask: flask, model: model)
        } catch {
            print("⚠️ \(flaskAssetName).usdz not found: a glowing orb stands in for the flask (\(error))")
            flask.addChild(makeStandIn())
            return ElixirRig(flask: flask, model: nil)
        }
    }

    /// The neck's two ends (top of the cork, bottom of the cork) in `space`: the ingredients dive along it.
    func neck(relativeTo space: Entity) -> (top: SIMD3<Float>, base: SIMD3<Float>) {
        (neckTop.position(relativeTo: space), neckBase.position(relativeTo: space))
    }

    /// Sparks bursting out of the flask the moment the elixir is brewed.
    func flash() {
        Self.burst(burst)
    }

    /// An ingredient lands in the liquid: a burst of bubbles.
    func splash() {
        Self.burst(bubbles)
    }

    /// Draws the flask's inside for the elixir's state: liquid level, colour, glow and slosh, the cork, the glass
    /// lighting up as an ingredient arrives, bubbles, the stream and the light. `pulse` makes the brewed elixir
    /// throb.
    func apply(_ state: Elixir, pulse: Float) {
        let fill = state.fillLevel
        let glowLevel = state.liquidGlow * pulse
        flask.orientation = simd_quatf(angle: state.wobble, axis: SIMD3(1, 0, 0)) * pourRotation(state.pourTilt)

        if let liquid {
            liquid.entity.isEnabled = fill > 0.002
            var scale = SIMD3<Float>(repeating: 1)
            scale[liquid.upAxis] = max(fill, 0.002)
            liquid.entity.scale = liquid.rest.scale * scale
            liquid.entity.orientation = liquid.rest.rotation * simd_quatf(angle: state.slosh, axis: liquid.slosh)
            let color = state.liquidColor
            let key = SIMD4(color, glowLevel)
            if appliedLiquid.map({ simd_distance($0, key) > 0.004 }) ?? true {
                liquid.model.model?.materials = [Self.liquidMaterial(color: color, glow: glowLevel)]
                appliedLiquid = key
            }
        }

        if let cork {
            let out = state.corkOut
            cork.entity.position = cork.rest.translation + cork.axis * (Self.corkRise * out)
                + cork.side * (Self.corkSide * out)
            cork.entity.orientation = simd_quatf(angle: 0.9 * .pi * out, axis: cork.side) * cork.rest.rotation
        }

        if let glass {
            let arrival = Elixir.ingredientColor(slot: max(state.orbitingCount - 1, 0))
            let key = SIMD4(arrival, state.arrivalGlow)
            if appliedGlass.map({ simd_distance($0, key) > 0.01 }) ?? true {
                glass.model?.materials = [Self.glassMaterial(glow: arrival, strength: state.arrivalGlow)]
                appliedGlass = key
            }
        }

        if var emitter = bubbles.components[ParticleEmitterComponent.self] {
            let rate: Float = fill > 0.05 && !state.isPouring ? 6 + 24 * fill * state.liquidGlow : 0
            if emitter.mainEmitter.birthRate != rate {
                emitter.mainEmitter.birthRate = rate
                bubbles.components.set(emitter)
            }
        }
        if var emitter = stream.components[ParticleEmitterComponent.self], emitter.isEmitting != state.isPouring {
            emitter.isEmitting = state.isPouring
            stream.components.set(emitter)
        }
        if var light = glow.components[PointLightComponent.self] {
            let intensity = 1800 * glowLevel * fill
            if abs(light.intensity - intensity) > 20 {
                light.intensity = intensity
                light.color = OrchardSceneBuilder.color(state.liquidColor)
                glow.components.set(light)
            }
        }
    }

    // MARK: - Pieces

    private static let sortGroup = ModelSortGroup()

    /// Tips the flask so its neck goes down (around the axis across the neck), `tilt` 0...1.
    private func pourRotation(_ tilt: Float) -> simd_quatf {
        guard tilt > 0 else { return simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)) }
        // In the flask's own space: the pour turns the flask itself.
        let neck = neckTop.position(relativeTo: flask) - neckBase.position(relativeTo: flask)
        let across = simd_cross(neck, SIMD3(0, 1, 0))
        guard simd_length(across) > 1e-5 else { return simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)) }
        return simd_quatf(angle: -Self.pourAngle * tilt, axis: simd_normalize(across))
    }

    private struct Parts {
        let liquid: Entity?
        let cork: Entity?
        let glass: Entity?
        let neckTop: Entity?
        let neckBase: Entity?
    }

    private static func parts(of model: Entity) -> Parts {
        Parts(liquid: model.findEntity(named: "Liquid"), cork: model.findEntity(named: "Cork"),
              glass: model.findEntity(named: "Glass"), neckTop: model.findEntity(named: "neck_top"),
              neckBase: model.findEntity(named: "neck_base"))
    }

    private static func liquidPart(_ entity: Entity?, flask: Entity) -> LiquidPart? {
        guard let entity, let model = firstModel(in: entity) else { return nil }
        // The asset keeps Blender's Z-up axes under its root's rotation: find which local axis points up.
        let up = entity.convert(direction: SIMD3(0, 1, 0), from: flask)
        let magnitudes = [abs(up.x), abs(up.y), abs(up.z)]
        let upAxis = magnitudes.firstIndex(of: magnitudes.max() ?? 0) ?? 1
        let across = simd_normalize(entity.convert(direction: SIMD3(1, 0, 0), from: flask))
        return LiquidPart(entity: entity, model: model, rest: entity.transform, upAxis: upAxis, slosh: across)
    }

    private static func corkPart(_ entity: Entity?, neckTop: Entity?, neckBase: Entity?) -> CorkPart? {
        guard let entity, let parent = entity.parent, let neckTop, let neckBase else { return nil }
        let axis = simd_normalize(neckTop.position(relativeTo: parent) - neckBase.position(relativeTo: parent))
        let reference: SIMD3<Float> = abs(axis.z) < 0.9 ? SIMD3(0, 0, 1) : SIMD3(1, 0, 0)
        return CorkPart(entity: entity, rest: entity.transform, axis: axis,
                        side: simd_normalize(simd_cross(axis, reference)))
    }

    private static func firstModel(in entity: Entity) -> ModelEntity? {
        if let model = entity as? ModelEntity { return model }
        for child in entity.children {
            if let model = firstModel(in: child) { return model }
        }
        return nil
    }

    private static func marker(at position: SIMD3<Float>, in parent: Entity) -> Entity {
        let marker = Entity()
        marker.position = position
        parent.addChild(marker)
        return marker
    }

    /// Clear glass: almost no roughness, a clear coat for the highlights, mostly see-through. Glows faintly in the
    /// colour of the ingredient that just reached the orbit.
    private static func glassMaterial(glow: SIMD3<Float>, strength: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.86, green: 0.93, blue: 1, alpha: 1))
        material.roughness = 0.04
        material.metallic = 0.0
        material.clearcoat = .init(floatLiteral: 1)
        material.clearcoatRoughness = .init(floatLiteral: 0.02)
        material.emissiveColor = .init(color: OrchardSceneBuilder.color(glow))
        material.emissiveIntensity = 1.5 * strength
        material.blending = .transparent(opacity: .init(floatLiteral: 0.22 + 0.2 * strength))
        return material
    }

    /// The liquid: tinted by the ingredients mixed in it, glowing, a little see-through.
    private static func liquidMaterial(color: SIMD3<Float>, glow: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: OrchardSceneBuilder.color(color))
        material.roughness = 0.15
        material.metallic = 0.0
        material.emissiveColor = .init(color: OrchardSceneBuilder.color(color))
        material.emissiveIntensity = 0.6 + 2.4 * glow
        material.blending = .transparent(opacity: .init(floatLiteral: 0.85))
        return material
    }

    /// Without the flask's asset: the glowing blue orb the elixir used to be.
    private static func makeStandIn() -> Entity {
        let orb = Entity()
        var core = PhysicallyBasedMaterial()
        core.baseColor = .init(tint: OrchardSceneBuilder.color(Elixir.elixirColor))
        core.emissiveColor = .init(color: OrchardSceneBuilder.color(Elixir.elixirColor))
        core.emissiveIntensity = 3
        core.roughness = 0.15
        orb.addChild(ModelEntity(mesh: .generateSphere(radius: 0.05), materials: [core]))
        return orb
    }

    private static func burst(_ entity: Entity) {
        guard var emitter = entity.components[ParticleEmitterComponent.self] else { return }
        emitter.burst()
        entity.components.set(emitter)
    }

    private static func makeBurst() -> Entity {
        let entity = Entity()
        var burst = ParticleEmitterComponent()
        burst.emitterShape = .sphere
        burst.emitterShapeSize = SIMD3(repeating: 0.06)
        burst.birthDirection = .normal
        burst.speed = 0.35
        burst.speedVariation = 0.15
        burst.isEmitting = false
        burst.burstCount = 160
        burst.mainEmitter.lifeSpan = 0.9
        burst.mainEmitter.size = 0.004
        burst.mainEmitter.color = .evolving(start: .single(UIColor(red: 0.85, green: 0.95, blue: 1, alpha: 1)),
                                            end: .single(OrchardSceneBuilder.color(Elixir.elixirColor)))
        entity.components.set(burst)
        return entity
    }

    /// Bubbles rising from the bottom of the round body (flask space: its origin is the body's centre).
    private static func makeBubbles() -> Entity {
        let entity = Entity()
        entity.position = SIMD3(0, -0.05, 0)
        var bubbles = ParticleEmitterComponent()
        bubbles.emitterShape = .sphere
        bubbles.emitterShapeSize = SIMD3(0.05, 0.02, 0.05)
        bubbles.birthDirection = .local
        bubbles.emissionDirection = SIMD3(0, 1, 0)
        bubbles.speed = 0.04
        bubbles.speedVariation = 0.015
        bubbles.burstCount = 40
        bubbles.mainEmitter.birthRate = 0
        bubbles.mainEmitter.lifeSpan = 1.1
        bubbles.mainEmitter.size = 0.004
        bubbles.mainEmitter.color = .constant(.single(UIColor(white: 1, alpha: 0.7)))
        entity.components.set(bubbles)
        return entity
    }

    /// Sparkling elixir pouring out of the neck (its direction is set along the neck) and falling.
    private static func makeStream() -> Entity {
        let entity = Entity()
        var stream = ParticleEmitterComponent()
        stream.emitterShape = .point
        stream.birthDirection = .local
        stream.speed = 0.25
        stream.speedVariation = 0.08
        stream.isEmitting = false
        stream.mainEmitter.birthRate = 220
        stream.mainEmitter.lifeSpan = 0.8
        stream.mainEmitter.size = 0.005
        stream.mainEmitter.acceleration = SIMD3(0, -1.2, 0)
        stream.mainEmitter.color = .evolving(start: .single(OrchardSceneBuilder.color(Elixir.elixirColor)),
                                             end: .single(UIColor(red: 0.85, green: 0.95, blue: 1, alpha: 1)))
        entity.components.set(stream)
        return entity
    }
}

// MARK: - System

extension OrchardSystem {
    /// The orbit follows the player (lazily) and turns; faster while the elixir brews.
    @MainActor
    static func updateOrbit(_ orchard: inout OrchardComponent, deltaTime: Float) {
        let viewModel = orchard.viewModel
        let elixir = viewModel.elixir
        let spin = elixir.state == .fusing
            ? 1 + orchard.orbit.settings.fusionSpin * Elixir.smootherstep(elixir.fusionProgress)
            : 1
        let viewer = orchard.viewer.viewerPose()
        orchard.orbit.follow(eyes: viewer.position, forward: viewer.forward, deltaTime: deltaTime, spin: spin)
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

    /// Draws the flask: appearing in the middle of the orbit with the first ingredient, turning slowly there,
    /// brewing (cork, dives, liquid), glowing with a flash, flying in an arc to the dragon's head and pouring the
    /// elixir over it.
    @MainActor
    static func updateElixir(_ orchard: inout OrchardComponent, root: Entity, deltaTime: Float) {
        let rig = orchard.elixir
        let state = orchard.viewModel.elixir
        let target = orchard.deliveryTarget.position(relativeTo: root)
        drawEvents(&orchard, target: target)

        let size = state.displayScale
        guard size > 0.001, !state.isFinished else {
            rig.elixir.isEnabled = false
            return
        }
        attach(rig.elixir, to: root, preservingWorldTransform: false)
        rig.elixir.isEnabled = true
        let pulse: Float = state.state == .brewed || state.state == .flying ? 1 + 0.1 * sin(orchard.time * 5) : 1
        switch state.state {
        case .gathering, .ready, .fusing:
            rig.elixir.position = orchard.orbit.center
        case .brewed:
            rig.elixir.position = orchard.orbit.center + SIMD3(0, 0.012 * sin(orchard.time * 2), 0)
        case .flying:
            guard var flight = orchard.flight else { return }
            flight.advance(deltaTime: deltaTime)
            orchard.flight = flight
            if flight.isArrived {
                orchard.viewModel.elixirDelivered()
            } else {
                rig.elixir.position = flight.position(towards: target)
            }
        case .delivered:
            // Above the dragon's head (it moves: the flask follows it while it pours).
            rig.elixir.position = target + SIMD3(0, ElixirRig.pourHeight, 0)
        }
        // Turning slowly on itself, so the player sees it from every side.
        rig.elixir.orientation = simd_quatf(angle: 0.4 * orchard.time, axis: SIMD3(0, 1, 0))
        rig.elixir.setScale(SIMD3(repeating: ElixirRig.flaskScale * size), relativeTo: nil)
        rig.apply(state, pulse: pulse)
    }

    /// The moments that happen once: the flash of the brewed elixir, the start of its flight, a splash for each
    /// ingredient landing in the flask.
    @MainActor
    private static func drawEvents(_ orchard: inout OrchardComponent, target: SIMD3<Float>) {
        let rig = orchard.elixir
        let state = orchard.viewModel.elixir
        if state.state != orchard.drawnElixirState {
            switch state.state {
            case .brewed: rig.flash()
            case .flying: orchard.flight = ElixirFlight(from: rig.elixir.position, to: target)
            case .gathering, .ready, .fusing, .delivered: orchard.flight = nil
            }
            orchard.drawnElixirState = state.state
        }
        let landed = state.landedCount
        if landed > orchard.drawnLandings { rig.splash() }
        orchard.drawnLandings = landed
    }
}
