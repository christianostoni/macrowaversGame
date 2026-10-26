import Foundation
import RealityKit
import simd
import UIKit

/// The ride on the dragon's back (`DragonRide`), drawn around the player: the dragon under them, a glow that brings
/// it out of the dark into the sky (an airbrushed dome, white clouds shaped like the tree's canopy, specks of air
/// rushing past), the rush of air. Then chapter II (`DragonFeast`): fruit float among the clouds and the dragon eats
/// the ones it likes, spitting out the bananas.
/// The player never moves: `root` stays at their eyes and the sky moves around it.
struct DragonRideComponent: Component {
    var ride = DragonRide()
    /// Chapter II's fruit, from the moment the player starts feeding the dragon.
    var feast: DragonFeast?
    let story: StoryViewModel
    let viewer: ViewerTracker
    let hands: HandTracker
    let rig: DragonRig
    let config: TangleConfig
    /// Holds the dragon: scaled up to a mount, leaning into the turns.
    let dragon: Entity
    /// Sky space (`DragonRide`): the clouds, the specks of air and the fruit live here.
    let sky: Entity
    let specks: [Entity]
    let clouds: [Entity]
    /// The airbrushed sky all around: it turns with the flight but never comes closer.
    let dome: Entity
    /// The glow that comes out of the dark when the ride begins.
    let beacon: Entity
    /// The dragon's mouth (in the dragon's holder): where the fruit go and its sounds come from.
    let mouth: Entity
    /// One model per fruit kind, cloned for the fruit in the sky.
    let fruitModels: [FruitKind: Entity]
    /// The fruit drawn in the sky, by `DragonFeast.Plant.id`, with the kind each one shows.
    var fruit: [Int: (entity: Entity, kind: FruitKind)] = [:]
    let sounds: [DragonRideSystem.Sound: AudioFileResource]
    let wind: AudioFileResource?
    var windController: AudioPlaybackController?
    /// The ride space has been set at the player's eyes.
    var isStarted = false
    /// Seconds waited for the head tracking before starting anyway (simulator, no tracking).
    var waitedForViewer: Float = 0
    var random = SystemRandomNumberGenerator()
}

struct DragonRideSystem: System {
    static let query = EntityQuery(where: .has(DragonRideComponent.self))

    /// The stone dragon (2.35 m) made big enough to ride: about 6 m long.
    static let dragonScale: Float = 2.6
    /// The player sits this far behind the head (m) and this high above the body.
    static let seat: Float = 1.4
    static let seatHeight: Float = 0.55
    /// From the head's node to the mouth, along the snout (m, ride scale).
    static let snout: Float = 0.4
    /// The specks of air: how many, and how far away they are recycled ahead of the player (m).
    static let speckCount = 160
    static let skyRadius: Float = 16
    /// The clouds: how many, how far away they are recycled ahead (m), how big (m across) and how close they come
    /// before fading (distance from their centre over their size), so the player never sits inside one.
    static let cloudCount = 40
    static let cloudRadius: Float = 110
    static let cloudSize: ClosedRange<Float> = 14...38
    static let cloudFade: ClosedRange<Float> = 0.4...1
    static let domeRadius: Float = 400
    /// A fruit in the sky (m tall).
    static let fruitSize: Float = 1.1
    /// Longest wait for the head tracking before the ride starts at the default eye height (s).
    static let viewerWait: Float = 1.5
    /// After the arrival, a moment of flight before chapter II's title appears (s).
    static let titleDelay: Float = 2

    enum Sound: String, CaseIterable {
        case appleOpen = "AppleOpen"
        case pineappleChop = "PineappleChop"
        case pomegranateBurst = "PomegranateBurst"
        case growl = "DragonGrowl"

        static func eating(_ fruit: FruitKind) -> Sound {
            switch fruit {
            case .pineapple: .pineappleChop
            case .pomegranate, .orange: .pomegranateBurst
            case .apple, .banana: .appleOpen
            }
        }
    }

    init(scene: RealityKit.Scene) {}

    @MainActor
    static func registerAll() {
        DragonRideComponent.registerComponent()
        registerSystem()
    }

    func update(context: SceneUpdateContext) {
        let deltaTime = Float(context.deltaTime)
        for root in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var state = root.components[DragonRideComponent.self] else { continue }
            if !state.isStarted {
                // The ride starts at the player's eyes: wait for the head tracking (a moment at most).
                state.waitedForViewer += deltaTime
                guard state.viewer.isTracking || state.waitedForViewer > Self.viewerWait else {
                    root.components.set(state)
                    continue
                }
                Self.start(&state, root: root)
            }

            let hands = state.hands.samples
            let left = hands[.left].map { root.convert(position: $0.knuckle, from: nil) }
            let right = hands[.right].map { root.convert(position: $0.knuckle, from: nil) }
            state.ride.holdHorns(left: left, right: right)
            state.ride.update(deltaTime: deltaTime, left: left, right: right,
                              isHandTrackingAvailable: state.hands.isTracking)

            Self.moveSky(&state)
            let mouth = Self.drawDragon(state, deltaTime: deltaTime)
            Self.drawArrival(state)
            Self.followStory(&state)
            Self.feed(&state, mouth: mouth, deltaTime: deltaTime)
            if let controller = state.windController {
                controller.gain = Self.windGain(state.ride)
            }
            root.components.set(state)
        }
    }

    // MARK: - Start

    /// The ride space: at the player's eyes, turned to where they look (level), as the room disappears.
    @MainActor
    private static func start(_ state: inout DragonRideComponent, root: Entity) {
        let (eyes, forward) = state.viewer.viewerPose()
        let yaw = atan2(-forward.x, -forward.z)
        root.transform = Transform(rotation: simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)), translation: eyes)
        if let wind = state.wind {
            let controller = root.prepareAudio(wind)
            controller.gain = -80
            controller.play()
            state.windController = controller
        }
        state.isStarted = true
    }

    // MARK: - Frame

    /// The sky turns and slides around the player; specks and clouds left behind come back far ahead.
    @MainActor
    private static func moveSky(_ state: inout DragonRideComponent) {
        let ride = state.ride
        let inverse = ride.orientation.inverse
        state.sky.transform = Transform(rotation: inverse, translation: -inverse.act(ride.position))
        state.dome.orientation = inverse
        for speck in state.specks {
            let offset = speck.position - ride.position
            guard simd_length(offset) > skyRadius else { continue }
            speck.position = ride.position + ride.orientation.act(randomAhead() * skyRadius * 0.97)
        }
        let daylight = smoothstep(0.55, 1, ride.arrival)
        for cloud in state.clouds {
            var distance = simd_length(cloud.position - ride.position)
            if distance > cloudRadius {
                // Far ahead, rarely right on the way: mostly below the dragon, some at its height to the sides.
                cloud.position = ride.position + ride.orientation.act(randomCloudSpot(distance: cloudRadius * 0.95))
                distance = cloudRadius * 0.95
            }
            let near = smoothstep(cloudFade.lowerBound, cloudFade.upperBound, distance / cloud.scale.x)
            cloud.components.set(OpacityComponent(opacity: daylight * near))
        }
    }

    /// The dragon under the player: its body along the flight, leaning into the turns. Returns its mouth (ride
    /// space).
    @MainActor
    private static func drawDragon(_ state: DragonRideComponent, deltaTime: Float) -> SIMD3<Float> {
        let ride = state.ride
        let scale = dragonScale
        let body = ride.body(count: state.config.nodeCount, spacing: state.config.segmentLength * scale,
                             seat: seat, seatHeight: seatHeight)
        // Right wing down in a right turn, about the axis through the player.
        let bank = simd_quatf(angle: -ride.bank, axis: SIMD3(0, 0, 1))
        state.dragon.orientation = bank
        let feast = state.feast
        let frame = DragonFrame(positions: body.map { $0 / scale }, mood: .calm, action: nil, actionProgress: 0,
                                restlessness: 0, strain: 0, time: ride.time, lookTarget: nil, viewer: .zero,
                                flight: FlightFrame(maneuver: .cruise, progress: 0,
                                                    velocity: SIMD3(0, 0, -ride.speed / scale),
                                                    bite: feast?.appetite ?? 0, disgust: feast?.disgust ?? 0))
        state.rig.update(frame, deltaTime: deltaTime)
        let snoutDirection = body.count > 1 ? simd_normalize(body[0] - body[1]) : SIMD3(0, 0, -1)
        let mouth = body[0] + snoutDirection * snout
        state.mouth.position = mouth / scale
        return bank.act(mouth)
    }

    /// Out of the dark: a glow far ahead comes to the player and fades as the dragon and the sky appear.
    @MainActor
    private static func drawArrival(_ state: DragonRideComponent) {
        let arrival = state.ride.arrival
        let approach = smoothstep(0, 0.7, arrival)
        state.beacon.position = SIMD3(0, -0.25 * approach, -9 + 7.5 * approach)
        let glow = smoothstep(0, 0.2, arrival) * (1 - smoothstep(0.6, 0.9, arrival))
        state.beacon.components.set(OpacityComponent(opacity: glow))
        state.beacon.isEnabled = glow > 0.001
        let daylight = smoothstep(0.55, 1, arrival)
        for entity in [state.dragon, state.dome] {
            if daylight >= 1 {
                entity.components.remove(OpacityComponent.self)
            } else {
                entity.components.set(OpacityComponent(opacity: daylight))
            }
        }
    }

    /// Chapter II's title once the dragon has flown out of the dark for a moment; the fruit once the player has
    /// read it.
    @MainActor
    private static func followStory(_ state: inout DragonRideComponent) {
        if state.story.step == .ride, state.ride.time > DragonRide.Settings.arrivalDuration + titleDelay {
            state.story.rideArrived()
        }
        if state.story.step == .feast, state.feast == nil {
            state.feast = DragonFeast(ride: state.ride, using: &state.random)
        }
    }

    /// The fruit in the sky: floating, swallowed, or spat out.
    @MainActor
    private static func feed(_ state: inout DragonRideComponent, mouth: SIMD3<Float>, deltaTime: Float) {
        guard var feast = state.feast else { return }
        let events = feast.update(deltaTime: deltaTime, mouth: state.ride.skyFromRide(mouth), ride: state.ride,
                                  using: &state.random)
        state.feast = feast
        for event in events {
            switch event {
            case .ate(let fruit):
                state.story.dragonAte(fruit)
                play(.eating(fruit), from: state.mouth, sounds: state.sounds)
            case .refused(let fruit):
                state.story.dragonAte(fruit)
                play(.growl, from: state.mouth, sounds: state.sounds)
            }
        }

        for plant in feast.plants {
            var drawn = state.fruit[plant.id]
            if drawn?.kind != plant.kind {
                drawn?.entity.removeFromParent()
                guard let model = state.fruitModels[plant.kind]?.clone(recursive: true) else { continue }
                state.sky.addChild(model)
                drawn = (model, plant.kind)
                state.fruit[plant.id] = drawn
            }
            guard let entity = drawn?.entity else { continue }
            entity.position = plant.position
            entity.orientation = simd_quatf(angle: plant.spin, axis: simd_normalize(SIMD3(0.3, 1, 0.2)))
            switch plant.state {
            case .floating:
                entity.scale = SIMD3(repeating: fruitSize)
                entity.components.remove(OpacityComponent.self)
            case .eaten(let progress):
                entity.scale = SIMD3(repeating: fruitSize * (1 - progress))
            case .spat(let progress, _):
                entity.components.set(OpacityComponent(opacity: 1 - smoothstep(0.5, 1, progress)))
            }
        }
    }

    @MainActor
    private static func play(_ sound: Sound, from entity: Entity, sounds: [Sound: AudioFileResource]) {
        guard let resource = sounds[sound] else { return }
        entity.playAudio(resource)
    }

    /// The rush of air (dB): grows from silence during the arrival, louder the faster the dragon flies.
    private static func windGain(_ ride: DragonRide) -> Double {
        let speed = (ride.speed - DragonRide.Settings.cruiseSpeed)
            / (DragonRide.Settings.boostSpeed - DragonRide.Settings.cruiseSpeed)
        let level = -16 + 9 * Double(max(0, min(speed, 1)))
        let fadeIn = Double(smoothstep(0.3, 1, ride.arrival))
        return fadeIn > 0.001 ? level + 20 * log10(fadeIn) : -80
    }

    /// A random direction in front of the player (ride space), within a wide cone.
    static func randomAhead() -> SIMD3<Float> {
        simd_normalize(SIMD3(Float.random(in: -1...1), Float.random(in: -0.8...0.8), -Float.random(in: 0.6...1.4)))
    }

    /// Where a cloud appears (ride space), `distance` away: a sea of clouds below, a few at the dragon's height
    /// off to the sides, now and then one high up.
    static func randomCloudSpot(distance: Float) -> SIMD3<Float> {
        let height: Float = switch Float.random(in: 0..<1) {
        case ..<0.6: -.random(in: 18...40)
        case ..<0.9: .random(in: -8...8)
        default: .random(in: 16...32)
        }
        let across = max(distance * distance - height * height, 1).squareRoot()
        // Ahead, in a wide fan, but never straight on the way at the dragon's height.
        var angle = Float.random(in: -1.1...1.1)
        if abs(height) < 12, abs(angle) < 0.3 { angle = angle < 0 ? -0.4 : 0.4 }
        return SIMD3(across * sin(angle), height, -across * cos(angle))
    }
}

private func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

// MARK: - Building

enum DragonRideSceneBuilder {
    static let rootName = "DragonRide"
    static let cloudAssetName = "RideCloud"
    static let skyTextureName = "RideSky"
    /// Where the story's page (chapter II's title) and the fruit tally float, in ride space (in front of the eyes,
    /// above the dragon's head).
    static let panelSpot = SIMD3<Float>(0, 0.02, -1.35)
    static let tallySpot = SIMD3<Float>(0, 0.34, -1.6)

    /// Builds the ride, ready to add to the scene (it starts on its first frame). nil when the stone dragon is not in
    /// the bundle.
    @MainActor
    static func makeRide(story: StoryViewModel, viewer: ViewerTracker, hands: HandTracker,
                         config: TangleConfig = TangleConfig()) async -> Entity? {
        guard let rig = await StoneDragonRig.load(config: config) else {
            print("⚠️ StoneDragon.usdz not found: no ride on the dragon's back")
            return nil
        }
        let root = Entity()
        root.name = rootName
        // The wind is all around the player, not coming from a point.
        root.components.set(AmbientAudioComponent())

        let dome = await makeDome()
        root.addChild(dome)

        let dragon = Entity()
        dragon.name = "RideDragon"
        dragon.scale = SIMD3(repeating: DragonRideSystem.dragonScale)
        dragon.components.set(OpacityComponent(opacity: 0))
        dragon.addChild(rig.entity)
        let mouth = Entity()
        mouth.name = "RideMouth"
        mouth.components.set(SpatialAudioComponent(gain: -4))
        dragon.addChild(mouth)
        root.addChild(dragon)

        let sky = Entity()
        sky.name = "RideSky"
        let specks = makeSpecks()
        specks.forEach { sky.addChild($0) }
        let clouds = await makeClouds()
        clouds.forEach { sky.addChild($0) }
        root.addChild(sky)

        let beacon = makeBeacon()
        root.addChild(beacon)

        var sounds: [DragonRideSystem.Sound: AudioFileResource] = [:]
        for sound in DragonRideSystem.Sound.allCases {
            sounds[sound] = await GameAudio.load(sound.rawValue)
        }
        root.components.set(DragonRideComponent(story: story, viewer: viewer, hands: hands, rig: rig, config: config,
                                                dragon: dragon, sky: sky, specks: specks, clouds: clouds, dome: dome,
                                                beacon: beacon, mouth: mouth, fruitModels: await makeFruitModels(),
                                                sounds: sounds, wind: await GameAudio.load("RideWind", loops: true)))
        return root
    }

    /// The airbrushed sky (`RideSky.jpg`, painted by `Assets/Blender/ride-sky/make_ride_sky.py`) on the inside of a
    /// big sphere. Without the texture the dark sky stays, with its specks.
    @MainActor
    private static func makeDome() async -> Entity {
        let dome = Entity()
        dome.name = "RideDome"
        dome.components.set(OpacityComponent(opacity: 0))
        guard let url = Bundle.main.url(forResource: skyTextureName, withExtension: "jpg"),
              let texture = try? await TextureResource(contentsOf: url, options: .init(semantic: .color)) else {
            print("⚠️ \(skyTextureName).jpg not found: the ride stays in the dark sky")
            return dome
        }
        // The painted colours as they are (tone mapping washes them out), seen from inside.
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(texture: .init(texture))
        material.faceCulling = .front
        dome.addChild(ModelEntity(mesh: .generateSphere(radius: DragonRideSystem.domeRadius), materials: [material]))
        return dome
    }

    /// White clouds made of the tree canopy's low-poly puffs (`RideCloud.usdz`, made by
    /// `Assets/Blender/ride-sky/make_cloud_asset.py`), scattered around the player, each its own size and turn.
    @MainActor
    private static func makeClouds() async -> [Entity] {
        guard let cloud = try? await Entity(named: cloudAssetName, in: .main) else {
            print("⚠️ \(cloudAssetName).usdz not found: no clouds in the sky")
            return []
        }
        return (0..<DragonRideSystem.cloudCount).map { _ in
            let copy = cloud.clone(recursive: true)
            copy.scale = SIMD3(repeating: .random(in: DragonRideSystem.cloudSize))
            copy.orientation = simd_quatf(angle: .random(in: 0..<(2 * .pi)), axis: SIMD3(0, 1, 0))
            let distance = Float.random(in: 25...DragonRideSystem.cloudRadius)
            var spot = DragonRideSystem.randomCloudSpot(distance: distance)
            // All around the player at first, not only ahead.
            spot = simd_quatf(angle: .random(in: 0..<(2 * .pi)), axis: SIMD3(0, 1, 0)).act(spot)
            copy.position = spot
            copy.components.set(OpacityComponent(opacity: 0))
            return copy
        }
    }

    /// The fruit floating in the sky, centred and one metre tall (`DragonRideSystem.fruitSize` scales them): the
    /// design team's fruit, whole, without their ingredient gems; the orange is the orchard's own.
    @MainActor
    private static func makeFruitModels() async -> [FruitKind: Entity] {
        var models: [FruitKind: Entity] = [:]
        for (kind, name) in [(FruitKind.apple, "Apple"), (.pineapple, "Pineapple"), (.pomegranate, "Pomegranate"),
                             (.banana, "Banana")] {
            guard let asset = try? await Entity(named: name, in: .main) else { continue }
            asset.findEntity(named: "gem")?.removeFromParent()
            models[kind] = normalised(asset)
        }
        if let orange = OrangeRig() {
            models[.orange] = normalised(orange.root)
        }
        return models
    }

    /// `model` centred in a holder, one metre tall.
    @MainActor
    private static func normalised(_ model: Entity) -> Entity {
        let holder = Entity()
        let bounds = model.visualBounds(relativeTo: nil)
        let height = max(bounds.extents.y, 0.001)
        model.scale /= height
        model.position = -bounds.center / height
        holder.addChild(model)
        return holder
    }

    /// Specks of air scattered all around the player: they show the speed (stars in the dark, motes in the sky).
    @MainActor
    private static func makeSpecks() -> [Entity] {
        let mesh = MeshResource.generateSphere(radius: 1)
        let tints: [UIColor] = [
            UIColor(white: 1, alpha: 1),
            UIColor(red: 0.85, green: 0.9, blue: 1, alpha: 1),
            UIColor(red: 0.7, green: 0.75, blue: 1, alpha: 1),
        ]
        let materials = tints.map { UnlitMaterial(color: $0) }
        return (0..<DragonRideSystem.speckCount).map { index in
            let speck = ModelEntity(mesh: mesh, materials: [materials[index % materials.count]])
            speck.scale = SIMD3(repeating: .random(in: 0.006...0.022))
            // Anywhere in the sky around the player (not too close to their face).
            var point = SIMD3<Float>(.random(in: -1...1), .random(in: -1...1), .random(in: -1...1))
            while simd_length(point) > 1 || simd_length(point) < 0.15 {
                point = SIMD3(.random(in: -1...1), .random(in: -1...1), .random(in: -1...1))
            }
            speck.position = point * DragonRideSystem.skyRadius
            return speck
        }
    }

    /// The small blue glow that comes out of the dark (the storyboard's third frame).
    @MainActor
    private static func makeBeacon() -> Entity {
        let beacon = Entity()
        beacon.name = "RideBeacon"
        let core = ModelEntity(mesh: .generateSphere(radius: 0.06),
                               materials: [UnlitMaterial(color: UIColor(red: 0.55, green: 0.65, blue: 1, alpha: 1))])
        var haze = UnlitMaterial(color: UIColor(red: 0.3, green: 0.4, blue: 1, alpha: 1))
        haze.blending = .transparent(opacity: 0.25)
        let halo = ModelEntity(mesh: .generateSphere(radius: 0.16), materials: [haze])
        beacon.addChild(core)
        beacon.addChild(halo)
        beacon.components.set(OpacityComponent(opacity: 0))
        return beacon
    }
}
