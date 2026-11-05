import RealityKit
import simd

/// The thin ring of light under the fruit in front of the player (`RingTurn`): pinch it and slide round it to turn
/// the fruit. It comes once the fruit has arrived from the tree and leaves when the fruit goes back.
struct TurnRingComponent: Component {
    /// The fruit's holder the ring turns (nil while it is hidden).
    var fruit: Entity?
    /// The pinch's last angle round the ring, while it slides.
    var dragAngle: Float?
}

@MainActor
enum TurnRing {
    static let name = "FruitTurnRing"
    /// The ring's line in its texture: radius (share of the square's half width) and half width.
    static let lineRadius: Float = 0.75
    static let lineWidth: Float = 0.012
    static let colour = RidePalette.paleGold
    /// How fast it fades in and out (1/s), and its brightness while a pinch turns it (it is 0.8 otherwise).
    static let fade: Float = 5
    static let rest: Float = 0.8
    static let turning: Float = 1
    /// Hit boxes round the ring (the middle stays free for the fruit's own gestures), in ring units (the ring's
    /// scale is its radius over `lineRadius`).
    static let hitBoxes = 24
    static let hitThickness: Float = 0.28

    /// The ring, hidden, to add under the orchard's stage. nil without its texture.
    static func make() async -> Entity? {
        guard let texture = await GlowTexture.ring(radius: lineRadius, width: lineWidth) else { return nil }
        let ring = Entity()
        ring.name = name
        ring.components.set(TurnRingComponent())
        ring.components.set(OpacityComponent(opacity: 0))
        ring.isEnabled = false
        let material = GlowTexture.material(texture, colour: RidePalette.uiColor(colour))
        // Flat, facing up: seen from above and below.
        ring.addChild(ModelEntity(mesh: .generatePlane(width: 2, depth: 2), materials: [material]))

        let step = 2 * Float.pi / Float(hitBoxes)
        let shapes = (0..<hitBoxes).map { index in
            let angle = Float(index) * step
            let size = SIMD3(lineRadius * step * 1.1, hitThickness * 0.8, hitThickness)
            return ShapeResource.generateBox(size: size)
                .offsetBy(rotation: simd_quatf(angle: angle, axis: SIMD3(0, 1, 0)),
                          translation: SIMD3(lineRadius * sin(angle), 0, lineRadius * cos(angle)))
        }
        ring.components.set(CollisionComponent(shapes: shapes))
        ring.components.set(InputTargetComponent())
        return ring
    }

    /// Shows the ring under `fruit` (a holder under the ring's parent, the stage) once it has arrived, or hides it
    /// (nil). Placed once per fruit: as it opens and turns, its bounds change, the ring stays.
    static func update(_ ring: Entity, fruit: Entity?, deltaTime: Float) {
        guard var state = ring.components[TurnRingComponent.self] else { return }
        if let fruit, state.fruit !== fruit, let parent = ring.parent {
            let bounds = fruit.visualBounds(relativeTo: parent)
            let (centre, radius) = RingTurn.placement(min: bounds.min, max: bounds.max)
            ring.position = centre
            ring.orientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
            ring.scale = SIMD3(repeating: radius / lineRadius)
            state.dragAngle = nil
            ring.isEnabled = true
        }
        state.fruit = fruit
        if fruit == nil { state.dragAngle = nil }
        ring.components.set(state)

        let target: Float = fruit == nil ? 0 : (state.dragAngle == nil ? rest : turning)
        let opacity = ring.components[OpacityComponent.self]?.opacity ?? 0
        let next = opacity + (target - opacity) * (1 - exp(-deltaTime * fade))
        ring.components.set(OpacityComponent(opacity: next))
        if fruit == nil, next < 0.01 { ring.isEnabled = false }
        ring.components[InputTargetComponent.self]?.isEnabled = fruit != nil
    }

    /// A pinch on the ring at `point` (ring space) slides round it: the fruit turns with it about the ring's axis.
    static func drag(_ ring: Entity, to point: SIMD3<Float>) {
        guard var state = ring.components[TurnRingComponent.self], let fruit = state.fruit else { return }
        let angle = RingTurn.angle(of: point)
        if let last = state.dragAngle {
            let turn = simd_quatf(angle: RingTurn.turn(from: last, to: angle), axis: SIMD3(0, 1, 0))
            // The ring and the fruit share their parent (the stage): its upright axis is the ring's.
            fruit.orientation = turn * fruit.orientation
        }
        state.dragAngle = angle
        ring.components.set(state)
    }

    static func endDrag(_ ring: Entity) {
        ring.components[TurnRingComponent.self]?.dragAngle = nil
    }
}
