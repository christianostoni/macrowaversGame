import RealityKit
import simd
import UIKit

/// The orange drawn in RealityKit, generated in code: eight wedges, each a full slice from the axis to the skin, with
/// juicy flesh, a white core and a white rind line on its cut faces. Pulled apart with two hands it first splits into
/// two halves that turn their cut faces to the player, like the pomegranate, then falls open into its eight wedges,
/// a ring around the orb. The opening comes from `OrchardViewModel`. Origin at the centre of the fruit.
@MainActor
final class OrangeRig {
    let root = Entity()
    /// Where the orb sits until it rises out of the opened orange (centre of the fruit).
    let orbAnchor = Entity()
    let radius: Float = 0.04
    /// Height of the fruit (metres).
    let size: Float
    /// From the orb anchor to the top of the orange.
    let heightAboveAnchor: Float

    private struct Wedge {
        let entity: Entity
        /// Horizontal, from the axis out through the middle of the wedge.
        let outward: SIMD3<Float>
        /// Horizontal, along the wedge's outer edge: the wedge tilts about it as it falls open.
        let tangent: SIMD3<Float>
    }

    private let body = Entity()
    /// Moved and turned to split the orange in two; each holds four wedges.
    private let rightPivot = Entity()
    private let leftPivot = Entity()
    private var wedges: [Wedge] = []
    private var appliedOpening: Float = -1
    /// Opening currently drawn: eases towards the requested one, so the wedges never snap shut.
    private var displayedOpening: Float = 0

    /// Slightly flattened at the poles, like a real orange.
    private static let squash: Float = 0.94
    private static let wedgesPerHalf = 4
    /// Half the gap between two wedges (radians of azimuth).
    private static let seam: Float = 0.004
    /// Bands of a cut face, as fractions of the radius: white core up to `coreScale`, flesh up to `fleshScale`, then rind.
    private static let coreScale: Float = 0.12
    private static let fleshScale: Float = 0.94
    /// How far each half moves sideways once split (metres); it comes half the way back as the wedges fall open.
    private static let halfShift: Float = 0.03
    /// How far each half turns its cut face towards the player (radians); it turns back as the wedges fall open.
    private static let halfTurn: Float = 0.15 * .pi
    /// Fully open, how far each wedge has moved out from the axis (metres) and tilted its top outwards (radians).
    private static let wedgeOut: Float = 0.03
    private static let wedgeTilt: Float = 0.7

    init?() {
        let skin = Self.material(red: 0.98, green: 0.45, blue: 0.04, roughness: 0.55, clearcoat: 0.3)
        let flesh = Self.material(red: 1, green: 0.52, blue: 0.06, roughness: 0.25, clearcoat: 0.6)
        let pith = Self.material(red: 1, green: 0.93, blue: 0.82, roughness: 0.9)
        let stem = Self.material(red: 0.3, green: 0.4, blue: 0.12, roughness: 0.7)
        size = 2 * radius * Self.squash
        heightAboveAnchor = radius * Self.squash

        let span = Float.pi / Float(Self.wedgesPerHalf)
        for (pivot, halfCentre) in [(rightPivot, Float(0)), (leftPivot, Float.pi)] {
            for index in 0..<Self.wedgesPerHalf {
                let start = halfCentre - .pi / 2 + span * Float(index)
                let azimuth = (start + Self.seam)...(start + span - Self.seam)
                guard let mesh = try? Self.makeWedgeMesh(azimuth: azimuth, radius: radius) else { return nil }
                let wedge = ModelEntity(mesh: mesh, materials: [skin, flesh, pith])
                pivot.addChild(wedge)
                let centre = start + span / 2
                wedges.append(Wedge(entity: wedge, outward: Self.radialDirection(azimuth: centre),
                                    tangent: Self.azimuthDirection(azimuth: centre)))
            }
            body.addChild(pivot)
        }
        // The stem stays on one wedge.
        let nub = ModelEntity(mesh: .generateCylinder(height: 0.004, radius: 0.0035), materials: [stem])
        nub.position = SIMD3(0, radius * Self.squash + 0.0015, 0)
        wedges.first?.entity.addChild(nub)

        // Target of the two-handed gesture that pulls it apart. Covers the wedges even fully open, so pulling
        // them apart or pushing them back together always lands on the fruit.
        body.components.set(OrangeBodyComponent())
        body.components.set(CollisionComponent(shapes: [
            .generateBox(width: 2 * (Self.halfShift + Self.wedgeOut + radius * 1.2), height: radius * 2.2,
                         depth: 2 * (Self.wedgeOut + radius * 1.2)),
        ]))
        body.components.set(InputTargetComponent.disabled)
        root.addChild(body)
        root.addChild(orbAnchor)
        apply(opening: 0)
    }

    // MARK: - Updates from the view model

    /// Moves the drawn opening towards `target` (quick while pulling, gentle when the orange closes again).
    func ease(towards target: Float, deltaTime: Float) {
        let rate: Float = target < displayedOpening ? 4 : 14
        displayedOpening += (target - displayedOpening) * (1 - exp(-deltaTime * rate))
        if abs(target - displayedOpening) < 0.002 { displayedOpening = target }
        apply(opening: displayedOpening)
    }

    /// 0 = whole; up to 0.5 the halves move apart and turn their cut faces to the player; up to 1 the wedges fall
    /// open: each moves out from the axis and tilts its top outwards, a ring of wedges around the orb.
    func apply(opening: Float) {
        guard opening != appliedOpening else { return }
        appliedOpening = opening
        let split = min(opening / 0.5, 1)
        let fall = min(max((opening - 0.5) / 0.5, 0), 1)
        let distance = split * Self.halfShift * (1 - fall / 2)
        let angle = split * Self.halfTurn * (1 - fall)
        rightPivot.position = SIMD3(distance, 0, 0)
        rightPivot.orientation = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
        leftPivot.position = SIMD3(-distance, 0, 0)
        leftPivot.orientation = simd_quatf(angle: -angle, axis: SIMD3(0, 1, 0))
        for wedge in wedges {
            // Turning about the tangent by a negative angle moves the top outwards.
            wedge.entity.orientation = simd_quatf(angle: -fall * Self.wedgeTilt, axis: wedge.tangent)
            wedge.entity.position = fall * Self.wedgeOut * wedge.outward
        }
    }

    func setInteractive(_ isInteractive: Bool) {
        body.components[InputTargetComponent.self]?.isEnabled = isInteractive
    }

    // MARK: - Building

    /// Triangles of one material, built up quad by quad.
    private struct MeshPart {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        /// Four corners in order around the quad.
        mutating func addQuad(_ corners: [SIMD3<Float>], normals cornerNormals: [SIMD3<Float>]) {
            let first = UInt32(positions.count)
            positions += corners
            normals += cornerNormals
            indices += [first, first + 1, first + 2, first, first + 2, first + 3]
        }

        mutating func addQuad(_ corners: [SIMD3<Float>], normal: SIMD3<Float>) {
            addQuad(corners, normals: Array(repeating: normal, count: corners.count))
        }

        func descriptor(name: String, material: UInt32) -> MeshDescriptor {
            var descriptor = MeshDescriptor(name: name)
            descriptor.positions = MeshBuffers.Positions(positions)
            descriptor.normals = MeshBuffers.Normals(normals)
            descriptor.primitives = .triangles(indices)
            descriptor.materials = .allFaces(material)
            return descriptor
        }
    }

    /// One wedge between two azimuths, from the axis to the skin: skin outside (material 0), and on both cut faces a
    /// white core, flesh (material 1) and a white rind line (material 2).
    private static func makeWedgeMesh(azimuth: ClosedRange<Float>, radius: Float) throws -> MeshResource {
        let rows = 18
        let columns = 9
        var skin = MeshPart()
        var flesh = MeshPart()
        var pith = MeshPart()
        let polar = { (row: Int) in Float.pi * Float(row) / Float(rows) }
        let along = { (column: Int) in
            azimuth.lowerBound + (azimuth.upperBound - azimuth.lowerBound) * Float(column) / Float(columns)
        }

        for row in 0..<rows {
            for column in 0..<columns {
                let corners = [(row, column), (row + 1, column), (row + 1, column + 1), (row, column + 1)]
                    .map { (polar: polar($0.0), azimuth: along($0.1)) }
                skin.addQuad(corners.map { surfacePoint(radius: radius, polar: $0.polar, azimuth: $0.azimuth) },
                             normals: corners.map { surfaceNormal(polar: $0.polar, azimuth: $0.azimuth) })
            }
        }

        let sides = [(azimuth.lowerBound, -azimuthDirection(azimuth: azimuth.lowerBound)),
                     (azimuth.upperBound, azimuthDirection(azimuth: azimuth.upperBound))]
        for (side, facing) in sides {
            // Between two scaled outlines of the fruit in the plane of this face (scale 0 = the axis).
            let band = { (inner: Float, outer: Float, row: Int) in
                [(inner, row), (inner, row + 1), (outer, row + 1), (outer, row)]
                    .map { surfacePoint(radius: radius * $0.0, polar: polar($0.1), azimuth: side) }
            }
            for row in 0..<rows {
                pith.addQuad(band(0, coreScale, row), normal: facing)
                flesh.addQuad(band(coreScale, fleshScale, row), normal: facing)
                pith.addQuad(band(fleshScale, 1, row), normal: facing)
            }
        }

        return try MeshResource.generate(from: [
            skin.descriptor(name: "skin", material: 0),
            flesh.descriptor(name: "flesh", material: 1),
            pith.descriptor(name: "pith", material: 2),
        ])
    }

    /// A point of the (slightly squashed) orange; azimuth 0 = +X, π/2 = +Z.
    private static func surfacePoint(radius: Float, polar: Float, azimuth: Float) -> SIMD3<Float> {
        radius * SIMD3(sin(polar) * cos(azimuth), squash * cos(polar), sin(polar) * sin(azimuth))
    }

    private static func surfaceNormal(polar: Float, azimuth: Float) -> SIMD3<Float> {
        simd_normalize(SIMD3(sin(polar) * cos(azimuth), cos(polar) / squash, sin(polar) * sin(azimuth)))
    }

    /// Horizontal, out from the axis.
    private static func radialDirection(azimuth: Float) -> SIMD3<Float> {
        SIMD3(cos(azimuth), 0, sin(azimuth))
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
