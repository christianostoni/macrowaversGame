import RealityKit
import simd

/// The pineapple's body: chop down through it with the hand, or tap it.
struct PineappleBodyComponent: Component {}

/// The pineapple drawn in RealityKit (`Pineapple.usdz`, the design team's, with Reality Composer Pro airbrush
/// materials): two halves split down the middle and a crown of leaves. Chopped, the halves fall open like a book
/// showing the flesh to the player and the crown tips away; sent back to the tree it closes gently. Origin at the
/// centre of the body.
@MainActor
final class PineappleRig {
    let root = Entity()
    /// Where the orb sits until it rises between the open halves.
    let orbAnchor = Entity()
    /// Height of the body, crown excluded (asset metres).
    let size: Float
    /// Radius of the body (asset metres).
    let radius: Float

    /// A half of the body and where it rests when whole.
    private struct Half {
        let entity: Entity
        let rest: Transform
        /// Which side of the cut it is on (−1 left, +1 right).
        let side: Float
    }

    private let hitBox = Entity()
    private var parts: [Half] = []
    private var crown: (entity: Entity, rest: Transform)?
    /// Opening currently drawn (0 = whole, 1 = chopped open).
    private(set) var displayedOpening: Float = 0
    private var appliedOpening: Float = -1

    init?() async {
        guard let asset = try? await Entity(named: "Pineapple", in: .main) else {
            print("⚠️ Pineapple.usdz not found: no pineapple on the tree")
            return nil
        }
        // The asset's golden gem: the orchard has its own orb.
        asset.findEntity(named: "gem")?.removeFromParent()
        let halves = ["pineapple_1", "pineapple_2"].compactMap { asset.findEntity(named: $0) }
        guard halves.count == 2 else { return nil }
        let body = halves.map { $0.visualBounds(relativeTo: asset) }.reduce(halves[0].visualBounds(relativeTo: asset)) {
            $0.union($1)
        }
        size = body.extents.y
        radius = max(body.extents.x, body.extents.z) / 2
        asset.position = -body.center
        root.addChild(asset)
        root.addChild(orbAnchor)

        for half in halves {
            let side: Float = half.visualBounds(relativeTo: asset).center.x < body.center.x ? -1 : 1
            parts.append(Half(entity: half, rest: half.transform, side: side))
        }
        if let crownEntity = asset.findEntity(named: "leaves") {
            crown = (crownEntity, crownEntity.transform)
        }

        hitBox.components.set(PineappleBodyComponent())
        // Covers the body and its open halves (they move 6 cm sideways each), and the base of the crown.
        hitBox.components.set(CollisionComponent(shapes: [
            .generateBox(width: 2 * (radius + 0.08), height: size * 1.3, depth: radius * 2.4)
                .offsetBy(translation: SIMD3(0, size * 0.1, 0)),
        ]))
        hitBox.components.set(InputTargetComponent.disabled)
        hitBox.components.set(HoverEffectComponent())
        root.addChild(hitBox)
    }

    // MARK: - Updates from the view model

    /// Moves the drawn opening towards `target` (quick when chopped, gentle when it closes again).
    func ease(towards target: Float, deltaTime: Float) {
        let rate: Float = target < displayedOpening ? 4 : 10
        displayedOpening += (target - displayedOpening) * (1 - exp(-deltaTime * rate))
        if abs(target - displayedOpening) < 0.002 { displayedOpening = target }
        apply(opening: displayedOpening)
    }

    /// 0 = whole, 1 = open: each half slides out and turns its cut face towards the player (+Z),
    /// the crown pops up and tips backwards.
    func apply(opening: Float) {
        guard opening != appliedOpening else { return }
        appliedOpening = opening
        for part in parts {
            var transform = part.rest
            transform.translation += SIMD3(part.side * 0.06 * opening, 0, 0)
            // The left half's cut face looks along +X: a negative turn about Y brings it towards +Z.
            transform.rotation = simd_quatf(angle: part.side * 0.42 * .pi * opening, axis: SIMD3(0, 1, 0)) * part.rest.rotation
            part.entity.transform = transform
        }
        if let crown {
            var transform = crown.rest
            transform.translation += SIMD3(0, 0.04 * opening, -0.1 * opening)
            transform.rotation = simd_quatf(angle: -0.6 * opening, axis: SIMD3(1, 0, 0)) * crown.rest.rotation
            crown.entity.transform = transform
        }
    }

    func setInteractive(_ isInteractive: Bool) {
        hitBox.components[InputTargetComponent.self]?.isEnabled = isInteractive
    }

    /// Where the hand must come down to chop the pineapple, in scene space.
    func chopTarget() -> ChopDetector.Target {
        let center = root.position(relativeTo: nil)
        let scale = root.scale(relativeTo: nil).x
        return ChopDetector.Target(center: center, baseY: center.y - size / 2 * scale,
                                   radius: radius * scale * 1.6 + 0.02, heightWindow: size * scale * 1.8)
    }
}
