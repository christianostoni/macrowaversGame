import RealityKit
import simd
import UIKit

/// A petal of the orange's peel: pinch it and pull it outwards and down. Holds the directions of its hinge (in
/// the hinge's parent space), so the gesture can turn the hand's position into how far the petal is pulled.
struct OrangePeelComponent: Component {
    let petal: Int
    /// Up, along the closed petal.
    let up: SIMD3<Float>
    /// Horizontal, from the orange's centre out through this petal.
    let outward: SIMD3<Float>
}

/// The orange drawn in RealityKit, generated in code: the peel is cut into petals that turn on hinges at their
/// bottom edge and open like a flower around the flesh. How far each petal is pulled comes from
/// `OrchardViewModel`. Origin at the centre of the fruit; petal 0 faces +Z (the player when focused).
@MainActor
final class OrangeRig {
    let root = Entity()
    /// Where the orb sits until it rises out of the peeled orange (centre of the flesh).
    let orbAnchor = Entity()
    let radius: Float = 0.04
    /// Height of the fruit (metres).
    let size: Float
    /// From the orb anchor to the top of the orange.
    let heightAboveAnchor: Float

    private struct Petal {
        let peel: Entity
        let hinge: Entity
        let restOrientation: simd_quatf
        let axis: SIMD3<Float>
    }

    private var petals: [Petal] = []
    /// Peel currently drawn: it eases towards the requested one, so the petals never snap shut.
    private(set) var displayedPeel = Array(repeating: Float(0), count: OrchardViewModel.orangePetals)

    /// Hinge angle of a petal hanging fully open (radians from upright, ≈ 137°).
    static let maxAngle: Float = 2.4
    /// Slightly flattened at the poles, like a real orange.
    private static let squash: Float = 0.94
    /// Polar angle of the cut between the petals and the base of the peel (0 = top, π = bottom).
    private static let hingePolar: Float = 0.75 * .pi
    /// Thickness of the peel, as a fraction of the radius.
    private static let peelThickness: Float = 0.06
    /// Half the gap between two petals (radians of azimuth).
    private static let seam: Float = 0.004

    init?() {
        let skin = Self.material(red: 0.98, green: 0.45, blue: 0.04, roughness: 0.55, clearcoat: 0.3)
        let pith = Self.material(red: 1, green: 0.93, blue: 0.82, roughness: 0.9)
        let flesh = Self.material(red: 1, green: 0.55, blue: 0.08, roughness: 0.3)
        let stem = Self.material(red: 0.3, green: 0.4, blue: 0.12, roughness: 0.7)
        size = 2 * radius * Self.squash
        heightAboveAnchor = radius * Self.squash

        let fleshBall = ModelEntity(mesh: .generateSphere(radius: radius * (1 - Self.peelThickness) * 0.97),
                                    materials: [flesh])
        fleshBall.scale = SIMD3(1, Self.squash, 1)
        root.addChild(fleshBall)
        root.addChild(orbAnchor)

        // The base of the peel stays on the flesh; the petals are hinged on its rim.
        guard let base = try? Self.makePeelMesh(radius: radius, polar: Self.hingePolar...Float.pi,
                                                azimuth: 0...(2 * Float.pi), origin: .zero) else { return nil }
        root.addChild(ModelEntity(mesh: base, materials: [skin, pith]))

        let span = 2 * Float.pi / Float(OrchardViewModel.orangePetals)
        for index in 0..<OrchardViewModel.orangePetals {
            let center = Float.pi / 2 + span * Float(index)
            let hingePosition = Self.surfacePoint(radius: radius, polar: Self.hingePolar, azimuth: center)
            let azimuth = (center - span / 2 + Self.seam)...(center + span / 2 - Self.seam)
            guard let mesh = try? Self.makePeelMesh(radius: radius, polar: 0...Self.hingePolar, azimuth: azimuth,
                                                    origin: hingePosition) else { return nil }
            let hinge = Entity()
            hinge.position = hingePosition
            let peel = ModelEntity(mesh: mesh, materials: [skin, pith])
            if index == 0 {
                // The stem comes away with the first petal, as when an orange is peeled by hand.
                let nub = ModelEntity(mesh: .generateCylinder(height: 0.004, radius: 0.0035), materials: [stem])
                nub.position = SIMD3(0, radius * Self.squash + 0.0015, 0) - hingePosition
                peel.addChild(nub)
            }
            hinge.addChild(peel)
            root.addChild(hinge)
            addPetal(index: index, peel: peel, hinge: hinge, center: .zero, up: SIMD3(0, 1, 0))
        }
    }

    // MARK: - Updates from the view model

    /// Moves the drawn petals towards `target` (quick while pulling, gentle when the orange closes again).
    func ease(towards target: [Float], deltaTime: Float) {
        for index in displayedPeel.indices where index < target.count {
            let rate: Float = target[index] < displayedPeel[index] ? 4 : 14
            displayedPeel[index] += (target[index] - displayedPeel[index]) * (1 - exp(-deltaTime * rate))
            if abs(target[index] - displayedPeel[index]) < 0.002 { displayedPeel[index] = target[index] }
        }
        for (index, petal) in petals.enumerated() where index < displayedPeel.count {
            petal.hinge.orientation = simd_quatf(angle: displayedPeel[index] * Self.maxAngle, axis: petal.axis)
                * petal.restOrientation
        }
    }

    /// The petals answer to the pinch only while the orange is close to the player.
    func setInteractive(_ isInteractive: Bool) {
        for petal in petals {
            petal.peel.components[InputTargetComponent.self]?.isEnabled = isInteractive
        }
    }

    /// How far the petal `peel` is pulled when the hand is at `handPosition` (scene space): 0 = closed,
    /// 1 = hanging fully open. The petal points at the hand, within the plane of its hinge.
    static func peelProgress(of peel: Entity, handPosition: SIMD3<Float>) -> Float? {
        guard let petal = peel.components[OrangePeelComponent.self], let hinge = peel.parent,
              let space = hinge.parent else { return nil }
        let toHand = space.convert(position: handPosition, from: nil) - hinge.position
        // 0 = upright, π/2 = horizontal outwards, more = hanging down outside.
        var angle = atan2(simd_dot(toHand, petal.outward), simd_dot(toHand, petal.up))
        if angle < 0 {
            // Slightly inside upright = closed; round past the bottom = fully open (it never snaps shut).
            angle = angle < -.pi / 2 ? maxAngle : 0
        }
        return min(max(angle, 0), maxAngle) / maxAngle
    }

    // MARK: - Building

    private func addPetal(index: Int, peel: Entity, hinge: Entity, center: SIMD3<Float>, up: SIMD3<Float>) {
        var outward = hinge.position - center
        outward -= simd_dot(outward, up) * up
        outward = simd_normalize(outward)
        peel.components.set(OrangePeelComponent(petal: index, up: up, outward: outward))
        // One box per slice of the petal: a single box would swallow the neighbouring petals.
        let shapes = peel.stackedBoxShapes(segments: 6, padding: 0.004)
        peel.components.set(CollisionComponent(shapes: shapes.isEmpty ? [.generateBox(size: SIMD3(repeating: 0.03))] : shapes))
        peel.components.set(InputTargetComponent.disabled)
        peel.components.set(HoverEffectComponent())
        petals.append(Petal(peel: peel, hinge: hinge, restOrientation: hinge.orientation,
                            axis: simd_normalize(simd_cross(up, outward))))
    }

    /// A grid of points on a piece of the peel, between two polar and two azimuth angles.
    @MainActor
    private struct PeelGrid {
        let radius: Float
        let polar: ClosedRange<Float>
        let azimuth: ClosedRange<Float>
        /// Subtracted from every position.
        let origin: SIMD3<Float>
        let rows = 18
        var columns: Int { max(Int((azimuth.upperBound - azimuth.lowerBound) / (2 * .pi) * 72), 6) }
        var innerRadius: Float { radius * (1 - OrangeRig.peelThickness) }
        var isRing: Bool { azimuth.upperBound - azimuth.lowerBound > 2 * .pi - 1e-3 }

        func angles(_ row: Int, _ column: Int) -> (polar: Float, azimuth: Float) {
            (polar.lowerBound + (polar.upperBound - polar.lowerBound) * Float(row) / Float(rows),
             azimuth.lowerBound + (azimuth.upperBound - azimuth.lowerBound) * Float(column) / Float(columns))
        }

        /// On the skin (`inside` false) or on the pith.
        func position(_ row: Int, _ column: Int, inside: Bool) -> SIMD3<Float> {
            let point = angles(row, column)
            return OrangeRig.surfacePoint(radius: inside ? innerRadius : radius, polar: point.polar,
                                          azimuth: point.azimuth) - origin
        }
    }

    /// A piece of the peel: the skin outside (material 0), the pith inside and along the cut edges (material 1).
    /// Positions relative to `origin`.
    private static func makePeelMesh(radius: Float, polar: ClosedRange<Float>, azimuth: ClosedRange<Float>,
                                     origin: SIMD3<Float>) throws -> MeshResource {
        let grid = PeelGrid(radius: radius, polar: polar, azimuth: azimuth, origin: origin)
        var outsidePositions: [SIMD3<Float>] = []
        var insidePositions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        for row in 0...grid.rows {
            for column in 0...grid.columns {
                let point = grid.angles(row, column)
                outsidePositions.append(grid.position(row, column, inside: false))
                insidePositions.append(grid.position(row, column, inside: true))
                normals.append(surfaceNormal(polar: point.polar, azimuth: point.azimuth))
            }
        }
        var indices: [UInt32] = []
        for row in 0..<grid.rows {
            for column in 0..<grid.columns {
                let first = UInt32(row * (grid.columns + 1) + column)
                let below = first + UInt32(grid.columns + 1)
                indices += [first, below, first + 1, first + 1, below, below + 1]
            }
        }

        var outside = MeshDescriptor(name: "skin")
        outside.positions = MeshBuffers.Positions(outsidePositions)
        outside.normals = MeshBuffers.Normals(normals)
        outside.primitives = .triangles(indices)
        outside.materials = .allFaces(0)

        var inside = MeshDescriptor(name: "pith")
        inside.positions = MeshBuffers.Positions(insidePositions)
        inside.normals = MeshBuffers.Normals(normals.map { -$0 })
        inside.primitives = .triangles(indices)
        inside.materials = .allFaces(1)

        return try MeshResource.generate(from: [outside, inside, makeEdges(of: grid)])
    }

    /// The cut edges of a piece of the peel: one quad from skin to pith per step along its border, facing out.
    private static func makeEdges(of grid: PeelGrid) -> MeshDescriptor {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        func addEdge(from start: (Int, Int), to end: (Int, Int), facing: (Float, Float) -> SIMD3<Float>) {
            let first = UInt32(positions.count)
            for (row, column) in [start, end] {
                let point = grid.angles(row, column)
                let normal = simd_normalize(facing(point.polar, point.azimuth))
                positions += [grid.position(row, column, inside: false), grid.position(row, column, inside: true)]
                normals += [normal, normal]
            }
            indices += [first, first + 1, first + 2, first + 2, first + 1, first + 3]
        }
        if !grid.isRing {
            for row in 0..<grid.rows {
                addEdge(from: (row, 0), to: (row + 1, 0)) { -azimuthDirection(azimuth: $1) }
                addEdge(from: (row, grid.columns), to: (row + 1, grid.columns)) { azimuthDirection(azimuth: $1) }
            }
        }
        for column in 0..<grid.columns {
            addEdge(from: (0, column), to: (0, column + 1)) { -polarTangent(polar: $0, azimuth: $1) }
            addEdge(from: (grid.rows, column), to: (grid.rows, column + 1)) { polarTangent(polar: $0, azimuth: $1) }
        }

        var edges = MeshDescriptor(name: "edges")
        edges.positions = MeshBuffers.Positions(positions)
        edges.normals = MeshBuffers.Normals(normals)
        edges.primitives = .triangles(indices)
        edges.materials = .allFaces(1)
        return edges
    }

    /// A point of the (slightly squashed) orange; azimuth 0 = +X, π/2 = +Z.
    private static func surfacePoint(radius: Float, polar: Float, azimuth: Float) -> SIMD3<Float> {
        radius * SIMD3(sin(polar) * cos(azimuth), squash * cos(polar), sin(polar) * sin(azimuth))
    }

    private static func surfaceNormal(polar: Float, azimuth: Float) -> SIMD3<Float> {
        simd_normalize(SIMD3(sin(polar) * cos(azimuth), cos(polar) / squash, sin(polar) * sin(azimuth)))
    }

    /// Along the surface, towards the bottom.
    private static func polarTangent(polar: Float, azimuth: Float) -> SIMD3<Float> {
        SIMD3(cos(polar) * cos(azimuth), -squash * sin(polar), cos(polar) * sin(azimuth))
    }

    /// Horizontal, towards growing azimuth.
    private static func azimuthDirection(azimuth: Float) -> SIMD3<Float> {
        SIMD3(-sin(azimuth), 0, cos(azimuth))
    }

    private static func material(red: CGFloat, green: CGFloat, blue: CGFloat, roughness: Float,
                                 clearcoat: Float = 0) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: red, green: green, blue: blue, alpha: 1))
        material.roughness = .init(floatLiteral: roughness)
        material.clearcoat = .init(floatLiteral: clearcoat)
        material.faceCulling = .none
        return material
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
