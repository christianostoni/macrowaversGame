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
    /// Heights above the dragon's head node (`deliveryTarget`), in metres. The dragon receives the elixir with its
    /// snout up (`DragonPhase.receivingElixir`), and the drawn head then rises up to ~9 cm above the node: its top is
    /// ~13 cm above it (`headTop`, where the elixir lands). The flask arrives upright with its centre at
    /// `arrivalHeight`, its bottom clear of the head, and tips over around its neck's mouth, held at `pourClearance`.
    static let arrivalHeight: Float = 0.32
    static let pourClearance: Float = 0.26
    static let headTop: Float = 0.13
    /// Particles per second of the stream and of the splash at full flow.
    static let streamRate: Float = 520
    static let splashRate: Float = 300

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
    /// What the pour leaves in the scene, upright in the orchard's root (not under the tipped flask, so the elixir
    /// falls straight down): the stream from the neck, the splash on the dragon's head and the shimmer once soothed.
    let pourEffects = Entity()
    private let stream: Entity
    private let splash: Entity
    private let shimmer: Entity
    /// The liquid's glow, lighting what is around the flask.
    private let glow: Entity
    /// The liquid's and the glass's materials, by their colour and glow in steps (`materialKey`): each is made once
    /// and only swapped when the step changes. Made anew whenever the colour moved a little, they were rebuilt
    /// almost every frame while the liquid mixed and the elixir throbbed.
    private var liquidMaterials: [SIMD4<Int32>: PhysicallyBasedMaterial] = [:]
    private var glassMaterials: [SIMD4<Int32>: PhysicallyBasedMaterial] = [:]
    private var appliedLiquid: SIMD4<Int32>?
    private var appliedGlass: SIMD4<Int32>?
    /// Light intensity already applied, in steps of `lightStep` (0 = no light component).
    private var appliedLight: Int?
    private var appliedLightColor: SIMD4<Int32>?

    /// The liquid: built for its level (`LiquidLevels`), filling the inside of the glass up to it, and sloshing around
    /// the centre of the flask's round body, so it never leaves the glass.
    private struct LiquidPart {
        let entity: Entity
        let model: ModelEntity
        let rest: Transform
        let levels: LiquidLevels?
        /// The centre of the round body, in the liquid's space: the liquid tilts around it.
        let pivot: SIMD3<Float>
        /// Its local axis pointing up in the flask (without `levels`, the liquid is scaled along it), and a
        /// horizontal one to slosh around.
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
        splash = Self.makeSplash()
        shimmer = Self.makeShimmer()
        glow = Entity()
        for effect in [burst, bubbles, glow] { flask.addChild(effect) }
        pourEffects.name = "ElixirPour"
        for effect in [stream, splash, shimmer] { pourEffects.addChild(effect) }

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
            let rig = ElixirRig(flask: flask, model: model)
            await rig.liquid?.levels?.prepare()
            return rig
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
    func splashIntoFlask() {
        Self.burst(bubbles)
    }

    /// The elixir streaming from the neck's mouth and landing on the dragon's head (both in `pourEffects`' space, the
    /// orchard's root), as strong as the pour's flow.
    func pour(_ state: Elixir, mouth: SIMD3<Float>, direction: SIMD3<Float>, head: SIMD3<Float>) {
        stream.position = mouth
        splash.position = head + SIMD3(0, Self.headTop, 0)
        shimmer.position = head
        Self.emit(stream, rate: Self.streamRate * state.pourFlow, direction: direction)
        Self.emit(splash, rate: Self.splashRate * state.splashFlow, direction: nil)
    }

    /// No stream, no splash (the shimmer, a burst, lives on by itself).
    func stopPouring() {
        Self.emit(stream, rate: 0, direction: nil)
        Self.emit(splash, rate: 0, direction: nil)
    }

    /// The last of the elixir has landed: the dragon is soothed, a shimmer rises around its head.
    func soothe() {
        Self.burst(shimmer)
    }

    /// The liquid at its level, tilted by the slosh around the centre of the round body: it stays inside the glass.
    private static func fill(_ liquid: LiquidPart, to fill: Float, slosh: Float) {
        liquid.entity.isEnabled = fill > 0.002
        let tilt = simd_quatf(angle: slosh, axis: liquid.slosh)
        liquid.entity.orientation = liquid.rest.rotation * tilt
        if let levels = liquid.levels {
            levels.show(fill)
            liquid.entity.position = liquid.rest.translation
                + liquid.rest.rotation.act(liquid.rest.scale * (liquid.pivot - tilt.act(liquid.pivot)))
        } else {
            // No mesh to take the glass's shape from: the old squash.
            var scale = SIMD3<Float>(repeating: 1)
            scale[liquid.upAxis] = max(fill, 0.002)
            liquid.entity.scale = liquid.rest.scale * scale
        }
    }

    /// Steps of colour (per channel) and of glow the materials change by: fine enough not to be seen.
    private static let colorSteps: Float = 24
    private static let glowSteps: Float = 12
    /// Steps of the light's intensity.
    private static let lightStep: Float = 60

    private static func materialKey(_ color: SIMD3<Float>, _ glow: Float) -> SIMD4<Int32> {
        let channels = SIMD3<Int32>(simd_clamp(color, .zero, .one) * colorSteps, rounding: .toNearestOrAwayFromZero)
        return SIMD4(channels, Int32((glow * glowSteps).rounded()))
    }

    private static func values(of key: SIMD4<Int32>) -> (color: SIMD3<Float>, glow: Float) {
        (SIMD3<Float>(Float(key.x), Float(key.y), Float(key.z)) / colorSteps, Float(key.w) / glowSteps)
    }

    /// Draws the flask's inside for the elixir's state: liquid level, colour, glow and slosh, the cork, the glass
    /// lighting up as an ingredient arrives, bubbles and the light. `pulse` makes the brewed elixir throb (through
    /// its light: the materials stay as they are).
    func apply(_ state: Elixir, pulse: Float) {
        let fill = state.fillLevel
        let glowLevel = state.liquidGlow
        flask.orientation = simd_quatf(angle: state.wobble, axis: SIMD3(1, 0, 0)) * pourRotation(state.pourTilt)

        if let liquid {
            Self.fill(liquid, to: fill, slosh: state.slosh)
            let key = Self.materialKey(state.liquidColor, glowLevel)
            if key != appliedLiquid {
                let material = liquidMaterials[key] ?? {
                    let values = Self.values(of: key)
                    return Self.liquidMaterial(color: values.color, glow: values.glow)
                }()
                liquidMaterials[key] = material
                liquid.model.model?.materials = [material]
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
            let key = Self.materialKey(arrival, state.arrivalGlow)
            if key != appliedGlass {
                let material = glassMaterials[key] ?? {
                    let values = Self.values(of: key)
                    return Self.glassMaterial(glow: values.color, strength: values.glow)
                }()
                glassMaterials[key] = material
                glass.model?.materials = [material]
                appliedGlass = key
            }
        }

        // Bubbles in steps of 3 a second: set every frame, the emitter was rebuilt every frame the liquid changed.
        let bubbleRate: Float = fill > 0.05 && !state.isPouring ? 6 + 24 * fill * glowLevel : 0
        Self.emit(bubbles, rate: (bubbleRate / 3).rounded() * 3, direction: nil)
        applyLight(intensity: 1800 * glowLevel * fill * pulse, color: state.liquidColor)
    }

    /// The liquid's light, in steps, and none at all while it is dark (a point light costs every surface near it).
    private func applyLight(intensity: Float, color: SIMD3<Float>) {
        let step = Int((intensity / Self.lightStep).rounded())
        let colorKey = Self.materialKey(color, 0)
        guard step != appliedLight || (step > 0 && colorKey != appliedLightColor) else { return }
        if step == 0 {
            glow.components.remove(PointLightComponent.self)
        } else {
            glow.components.set(PointLightComponent(color: OrchardSceneBuilder.color(Self.values(of: colorKey).color),
                                                    intensity: Float(step) * Self.lightStep, attenuationRadius: 0.6))
        }
        appliedLight = step
        appliedLightColor = colorKey
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
        let levels = LiquidLevels(model: model, up: model.convert(direction: SIMD3(0, 1, 0), from: flask))
        let pivot = levels.map { entity.convert(position: $0.volume.widestPoint, from: model) } ?? .zero
        return LiquidPart(entity: entity, model: model, rest: entity.transform, levels: levels, pivot: pivot,
                          upAxis: upAxis, slosh: across)
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
        // Where the flask flies: above the head, upright, its bottom clear of it.
        let arrival = target + SIMD3(0, ElixirRig.arrivalHeight, 0)
        drawEvents(&orchard, arrival: arrival)
        attach(rig.pourEffects, to: root, preservingWorldTransform: false)
        if state.state != .delivered { rig.stopPouring() }

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
                rig.elixir.position = flight.position(towards: arrival)
            }
        case .delivered, .poured:
            break
        }
        // Turning slowly on itself, so the player sees it from every side; pouring, it turns side-on to them.
        let spin = simd_quatf(angle: 0.4 * orchard.time, axis: SIMD3(0, 1, 0))
        rig.elixir.orientation = state.state == .delivered
            ? simd_slerp(spin, simd_quatf(angle: orchard.pourYaw, axis: SIMD3(0, 1, 0)),
                         Elixir.smootherstep(state.stateTime / Elixir.Pour.tipStart))
            : spin
        rig.elixir.setScale(SIMD3(repeating: ElixirRig.flaskScale * size), relativeTo: nil)
        rig.apply(state, pulse: pulse)
        if state.state == .delivered { pour(rig, state: state, head: target, arrival: arrival, root: root) }
    }

    /// The flask over the dragon's head (it moves: the flask follows it). Upright it waits at `arrival`; as it tips
    /// over it turns around its neck's mouth, held `pourClearance` above the head, so the glass never sinks into it
    /// and the elixir falls straight onto it.
    @MainActor
    private static func pour(_ rig: ElixirRig, state: Elixir, head: SIMD3<Float>, arrival: SIMD3<Float>,
                             root: Entity) {
        let mouthInFlask = rig.neck(relativeTo: rig.elixir).top
        let mouthOffset = rig.elixir.orientation.act(mouthInFlask * rig.elixir.scale.x)
        let anchored = head + SIMD3(0, ElixirRig.pourClearance, 0) - mouthOffset
        rig.elixir.position = simd_mix(arrival, anchored, SIMD3(repeating: state.pourTilt))
        let neck = rig.neck(relativeTo: root)
        let direction = simd_length(neck.top - neck.base) > 1e-5 ? simd_normalize(neck.top - neck.base) : SIMD3(0, -1, 0)
        rig.pour(state, mouth: neck.top, direction: direction, head: head)
    }

    /// The moments that happen once: the flash of the brewed elixir, the start of its flight, the side the flask
    /// turns to as it arrives, a splash for each ingredient landing in the flask, the shimmer of the soothed dragon.
    @MainActor
    private static func drawEvents(_ orchard: inout OrchardComponent, arrival: SIMD3<Float>) {
        let rig = orchard.elixir
        let state = orchard.viewModel.elixir
        if state.state != orchard.drawnElixirState {
            switch state.state {
            case .brewed: rig.flash()
            case .flying: orchard.flight = ElixirFlight(from: rig.elixir.position, to: arrival)
            case .delivered:
                orchard.flight = nil
                // The flask's tipping axis (its local z, across the neck) towards the player: they see it pour in
                // profile.
                let toViewer = orchard.viewer.viewerPose().position - arrival
                orchard.pourYaw = atan2(toViewer.x, toViewer.z)
            case .gathering, .ready, .fusing, .poured: orchard.flight = nil
            }
            orchard.drawnElixirState = state.state
        }
        let landed = state.landedCount
        if landed > orchard.drawnLandings { rig.splashIntoFlask() }
        orchard.drawnLandings = landed
        if state.hasSoothed && !orchard.drawnSoothed { rig.soothe() }
        orchard.drawnSoothed = state.hasSoothed
    }
}
