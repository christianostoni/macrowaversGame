import RealityKit
import simd

/// A strip of the banana's peel: pinch it and pull it outwards and down. Holds the directions of its hinge (in
/// the hinge's parent space), so the gesture can turn the hand's position into how far the strip is pulled.
struct BananaPeelComponent: Component {
    let strip: Int
    /// Up, along the closed strip.
    let up: SIMD3<Float>
    /// Horizontal, from the banana's centre out through this strip.
    let outward: SIMD3<Float>
}

/// The banana drawn in RealityKit (`Banana.usdz`, the design team's, with Reality Composer Pro airbrush materials):
/// four strips of peel turn on hinges at their bottom edge, like a banana peeled by hand. How far each strip is pulled comes from
/// `OrchardViewModel`. Origin at the centre of the fruit.
@MainActor
final class BananaRig {
    let root = Entity()
    /// Where the orb sits until it rises out of the peeled banana (centre of the flesh).
    let orbAnchor = Entity()
    /// Height of the fruit (asset metres).
    let size: Float
    /// From the orb anchor to the top of the banana.
    let heightAboveAnchor: Float

    private struct Strip {
        let peel: Entity
        let hinge: Entity
        let restOrientation: simd_quatf
        let axis: SIMD3<Float>
    }

    private var strips: [Strip] = []
    /// Peel currently drawn: it eases towards the requested one, so the strips never snap shut.
    private(set) var displayedPeel = Array(repeating: Float(0), count: OrchardViewModel.bananaStrips)

    /// Hinge angle of a strip hanging fully open (radians from upright, ≈ 137°).
    static let maxAngle: Float = 2.4

    init?() async {
        guard let asset = try? await Entity(named: "Banana", in: .main) else {
            print("⚠️ Banana.usdz not found: no banana on the tree")
            return nil
        }
        // The asset's golden gem: the orchard has its own orb.
        asset.findEntity(named: "gem")?.removeFromParent()
        let bounds = asset.visualBounds(relativeTo: asset)
        let flesh = asset.findEntity(named: "flesh")
        let coreCenter = flesh?.visualBounds(relativeTo: asset).center ?? bounds.center
        size = bounds.extents.y
        heightAboveAnchor = bounds.max.y - coreCenter.y

        let turn = Entity()
        // Two strips face the player instead of one edge-on (as in the prototype).
        turn.orientation = simd_quatf(angle: .pi / 4, axis: SIMD3(0, 1, 0))
        asset.position = -bounds.center
        turn.addChild(asset)
        root.addChild(turn)
        orbAnchor.position = coreCenter - bounds.center
        turn.addChild(orbAnchor)

        for index in 1...OrchardViewModel.bananaStrips {
            guard let peel = asset.findEntity(named: "peel_\(index)"), let hinge = peel.parent,
                  let space = hinge.parent else { continue }
            addStrip(index: index - 1, peel: peel, hinge: hinge, center: space.convert(position: coreCenter, from: asset),
                     up: simd_normalize(space.convert(direction: SIMD3(0, 1, 0), from: asset)))
        }
        guard !strips.isEmpty else { return nil }
    }

    // MARK: - Updates from the view model

    /// Moves the drawn strips towards `target` (quick while pulling, gentle when the banana closes again).
    func ease(towards target: [Float], deltaTime: Float) {
        for index in displayedPeel.indices where index < target.count {
            let rate: Float = target[index] < displayedPeel[index] ? 4 : 14
            displayedPeel[index] += (target[index] - displayedPeel[index]) * (1 - exp(-deltaTime * rate))
            if abs(target[index] - displayedPeel[index]) < 0.002 { displayedPeel[index] = target[index] }
        }
        for (index, strip) in strips.enumerated() where index < displayedPeel.count {
            strip.hinge.orientation = simd_quatf(angle: displayedPeel[index] * Self.maxAngle, axis: strip.axis)
                * strip.restOrientation
        }
    }

    /// The strips answer to the pinch only while the banana is close to the player.
    func setInteractive(_ isInteractive: Bool) {
        for strip in strips {
            strip.peel.components[InputTargetComponent.self]?.isEnabled = isInteractive
        }
    }

    /// How far the strip `peel` is pulled when the hand is at `handPosition` (scene space): 0 = closed,
    /// 1 = hanging fully open. The strip points at the hand, within the plane of its hinge.
    static func peelProgress(of peel: Entity, handPosition: SIMD3<Float>) -> Float? {
        guard let strip = peel.components[BananaPeelComponent.self], let hinge = peel.parent,
              let space = hinge.parent else { return nil }
        let toHand = space.convert(position: handPosition, from: nil) - hinge.position
        // 0 = upright, π/2 = horizontal outwards, more = hanging down outside.
        var angle = atan2(simd_dot(toHand, strip.outward), simd_dot(toHand, strip.up))
        if angle < 0 {
            // Slightly inside upright = closed; round past the bottom = fully open (it never snaps shut).
            angle = angle < -.pi / 2 ? maxAngle : 0
        }
        return min(max(angle, 0), maxAngle) / maxAngle
    }

    // MARK: - Building

    private func addStrip(index: Int, peel: Entity, hinge: Entity, center: SIMD3<Float>, up: SIMD3<Float>) {
        var outward = hinge.position - center
        outward -= simd_dot(outward, up) * up
        if simd_length(outward) < 1e-5 {
            outward = hinge.orientation.act(SIMD3(0, 0, 1))
            outward -= simd_dot(outward, up) * up
        }
        outward = simd_normalize(outward)
        peel.components.set(BananaPeelComponent(strip: index, up: up, outward: outward))
        // One box per slice of the strip: a single box would swallow the neighbouring strips.
        let shapes = peel.stackedBoxShapes(segments: 6, padding: 0.004)
        peel.components.set(CollisionComponent(shapes: shapes.isEmpty ? [.generateBox(size: SIMD3(repeating: 0.03))] : shapes))
        peel.components.set(InputTargetComponent.disabled)
        peel.components.set(HoverEffectComponent())
        strips.append(Strip(peel: peel, hinge: hinge, restOrientation: hinge.orientation,
                            axis: simd_normalize(simd_cross(up, outward))))
    }
}

extension Entity {
    /// Collision boxes that hug this entity's meshes: the vertices (in this entity's space) are cut into
    /// `segments` slices along local Y and each slice gets its own padded box.
    func stackedBoxShapes(segments: Int, padding: Float) -> [ShapeResource] {
        var points: [SIMD3<Float>] = []
        for entity in [self] + allDescendants {
            guard let model = entity.components[ModelComponent.self] else { continue }
            let contents = model.mesh.contents
            for instance in contents.instances {
                guard let mesh = contents.models[instance.model] else { continue }
                for part in mesh.parts {
                    for point in part.positions.elements {
                        let inModel = instance.transform * SIMD4<Float>(point, 1)
                        points.append(convert(position: SIMD3(inModel.x, inModel.y, inModel.z), from: entity))
                    }
                }
            }
        }
        guard let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(), maxY > minY else { return [] }

        let count = max(segments, 1)
        let step = (maxY - minY) / Float(count)
        var lower = Array(repeating: SIMD3<Float>(repeating: .infinity), count: count)
        var upper = Array(repeating: SIMD3<Float>(repeating: -.infinity), count: count)
        for point in points {
            let slice = min(Int((point.y - minY) / step), count - 1)
            lower[slice] = simd_min(lower[slice], point)
            upper[slice] = simd_max(upper[slice], point)
        }
        return (0..<count).compactMap { slice in
            guard lower[slice].x <= upper[slice].x else { return nil }
            let size = upper[slice] - lower[slice] + SIMD3(repeating: 2 * padding)
            return ShapeResource.generateBox(size: size).offsetBy(translation: (lower[slice] + upper[slice]) / 2)
        }
    }

    /// Every entity below this one, depth first.
    var allDescendants: [Entity] {
        children.flatMap { [$0] + $0.allDescendants }
    }
}
