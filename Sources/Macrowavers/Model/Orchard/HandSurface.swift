import Foundation
import simd

/// The hologram hand's skin: one smooth, closed surface around a `SnapHint.Pose`, with no joints showing.
/// Pure maths (Foundation + simd): `SnapHintRig` builds one mesh per frame of the loop, once, in the background.
///
/// The hand is a signed distance field (negative inside), in hand space (metres):
/// - the palm: a box with rounded edges, narrower at the wrist, and the ball of the thumb (a round cone along the
///   thumb's metacarpal) melted into it (`palmBlend`);
/// - each finger: three round cones, one per phalanx, tapering to the fingertip; their radii match at the joints,
///   so the finger is one smooth tube;
/// - each finger, and the thumb, melts into the palm at its base (`fingerBlend`), but never into its neighbours:
///   the hand is the plain union of (palm ⊕ finger) for every finger, so fingers pressed together stay apart.
///
///     smin(a, b, k) = min(a, b) − h² · k / 4,    h = max(k − |a − b|, 0) / k
///
/// The mesh comes from naive surface nets: one vertex per grid cell the surface crosses (the mean of the crossings
/// on its edges, then moved onto the surface along the field's gradient), one quad per grid edge the surface
/// crosses; the normals are the gradient's.
struct HandSurface {
    struct Mesh: Equatable {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
    }

    /// A round cone: a capsule from `start` (radius `startRadius`) to `end` (radius `endRadius`).
    struct Cone: Equatable {
        var start: SIMD3<Float>
        var end: SIMD3<Float>
        var startRadius: Float
        var endRadius: Float

        /// Signed distance (exact; Inigo Quilez's round cone).
        func distance(_ point: SIMD3<Float>) -> Float {
            let axis = end - start
            let lengthSquared = simd_length_squared(axis)
            let radiusDifference = startRadius - endRadius
            let slant = lengthSquared - radiusDifference * radiusDifference
            let relative = point - start
            let along = simd_dot(relative, axis)
            let beyond = along - lengthSquared
            let across = simd_length_squared(relative * lengthSquared - axis * along)
            let alongSquared = along * along * lengthSquared
            let beyondSquared = beyond * beyond * lengthSquared
            let edge = (radiusDifference < 0 ? -1 : 1) * radiusDifference * radiusDifference * across
            if (beyond < 0 ? -1 : 1) * slant * beyondSquared > edge {
                return (across + beyondSquared).squareRoot() / lengthSquared - endRadius
            }
            if (along < 0 ? -1 : 1) * slant * alongSquared < edge {
                return (across + alongSquared).squareRoot() / lengthSquared - startRadius
            }
            return ((across * slant / lengthSquared).squareRoot() + along * radiusDifference) / lengthSquared
                - startRadius
        }
    }

    /// Grid step of the mesh (m, hand space): ~5 steps across a fingertip.
    static let cellSize: Float = 0.0028
    /// How softly the ball of the thumb melts into the palm, and each finger into the palm (m).
    static let palmBlend: Float = 0.012
    static let fingerBlend: Float = 0.009
    /// The palm: centre, half-height, half-thickness, rounding (m); half-width at the wrist and its growth per metre
    /// of height (it widens towards the knuckles).
    static let palmCentre = SIMD3<Float>(0, 0.046, 0)
    static let palmHalfHeight: Float = 0.036
    static let palmHalfThickness: Float = 0.001
    static let palmRounding: Float = 0.012
    static let wristHalfWidth: Float = 0.017
    static let palmWidening: Float = 0.09
    /// Radius of each finger at its joints, as a share of its knuckle's (`SnapHint.Finger.radius`).
    static let taper = SIMD3<Float>(0.92, 0.84, 0.76)

    let thenar: Cone
    let thumb: [Cone]
    let fingers: [[Cone]]
    /// A sphere around each finger and around the thumb's phalanges (centre, radius): far from it, the finger
    /// cannot change the distance, and its cones are skipped (most of the grid is far from most fingers).
    private let fingerBounds: [SIMD4<Float>]
    private let thumbBound: SIMD4<Float>

    init(pose: SnapHint.Pose) {
        thenar = Cone(start: SnapHint.thumbBase, end: pose.thumb.base, startRadius: 0.016, endRadius: 0.0115)
        thumb = [Cone(start: pose.thumb.base, end: pose.thumb.joint, startRadius: 0.0115, endRadius: 0.0098),
                 Cone(start: pose.thumb.joint, end: pose.thumb.tip, startRadius: 0.0098,
                      endRadius: SnapHint.thumbTipRadius)]
        fingers = zip(SnapHint.fingers, pose.fingers).map(Self.cones)
        fingerBounds = fingers.map(Self.bound)
        thumbBound = Self.bound(thumb)
    }

    /// The smallest sphere around the cones' ends, grown by their widest radius (not the tightest, but enough).
    private static func bound(_ cones: [Cone]) -> SIMD4<Float> {
        let points = cones.flatMap { [$0.start, $0.end] }
        let centre = points.reduce(.zero, +) / Float(points.count)
        let reach = points.map { simd_distance($0, centre) }.max() ?? 0
        let radius = cones.map { max($0.startRadius, $0.endRadius) }.max() ?? 0
        return SIMD4(centre, reach + radius)
    }

    /// No closer to `point` than this (m).
    private static func lowerBound(_ bound: SIMD4<Float>, _ point: SIMD3<Float>) -> Float {
        simd_distance(point, SIMD3(bound.x, bound.y, bound.z)) - bound.w
    }

    /// A finger's three phalanges, from its knuckle through its `joints`, tapering.
    private static func cones(_ finger: SnapHint.Finger, joints: [SIMD3<Float>]) -> [Cone] {
        let radius = finger.radius
        let radii: [Float] = [radius, radius * taper.x, radius * taper.y, radius * taper.z]
        let points: [SIMD3<Float>] = [finger.knuckle] + joints
        return (0..<3).map { bone in
            Cone(start: points[bone], end: points[bone + 1], startRadius: radii[bone], endRadius: radii[bone + 1])
        }
    }

    static func smoothMin(_ first: Float, _ second: Float, _ blend: Float) -> Float {
        let weight = max(blend - abs(first - second), 0) / blend
        return min(first, second) - weight * weight * blend * 0.25
    }

    /// The palm alone: a rounded box, narrower at the wrist.
    static func palmDistance(_ point: SIMD3<Float>) -> Float {
        let halfWidth = wristHalfWidth + palmWidening * min(max(point.y, 0), 0.1)
        let offset = abs(point - palmCentre) - SIMD3(halfWidth, palmHalfHeight, palmHalfThickness)
        return simd_length(simd_max(offset, .zero)) + min(max(offset.x, max(offset.y, offset.z)), 0) - palmRounding
    }

    /// Signed distance to the hand's skin (m): negative inside.
    func distance(_ point: SIMD3<Float>) -> Float {
        let palm = Self.smoothMin(Self.palmDistance(point), thenar.distance(point), Self.palmBlend)
        // A finger at least `fingerBlend` farther than the palm leaves smin(palm, finger) = palm: skipped.
        let reach = palm + Self.fingerBlend
        var distance = palm
        if Self.lowerBound(thumbBound, point) < reach {
            distance = Self.smoothMin(palm, min(thumb[0].distance(point), thumb[1].distance(point)), Self.fingerBlend)
        }
        for (finger, bound) in zip(fingers, fingerBounds) where Self.lowerBound(bound, point) < reach {
            let tube = min(finger[0].distance(point), min(finger[1].distance(point), finger[2].distance(point)))
            distance = min(distance, Self.smoothMin(palm, tube, Self.fingerBlend))
        }
        return distance
    }

    /// The field's gradient, normalised: the skin's outward normal near `point`.
    func normal(at point: SIMD3<Float>) -> SIMD3<Float> {
        let step: Float = 0.0005
        let gradient = SIMD3<Float>(
            distance(point + SIMD3(step, 0, 0)) - distance(point - SIMD3(step, 0, 0)),
            distance(point + SIMD3(0, step, 0)) - distance(point - SIMD3(0, step, 0)),
            distance(point + SIMD3(0, 0, step)) - distance(point - SIMD3(0, 0, step)))
        let length = simd_length(gradient)
        return length > 1e-9 ? gradient / length : SIMD3(0, 0, 1)
    }

    /// A box around the whole hand (hand space), one radius out from every bone and the palm.
    var bounds: (lower: SIMD3<Float>, upper: SIMD3<Float>) {
        let palmHalf = SIMD3(wristHalfWidthAtTop, Self.palmHalfHeight, Self.palmHalfThickness)
            + SIMD3(repeating: Self.palmRounding)
        var lower = Self.palmCentre - palmHalf
        var upper = Self.palmCentre + palmHalf
        for cone in [thenar] + thumb + fingers.flatMap({ $0 }) {
            let radius = max(cone.startRadius, cone.endRadius)
            lower = simd_min(lower, simd_min(cone.start, cone.end) - radius)
            upper = simd_max(upper, simd_max(cone.start, cone.end) + radius)
        }
        return (lower, upper)
    }

    private var wristHalfWidthAtTop: Float { Self.wristHalfWidth + Self.palmWidening * 0.1 }

    /// The skin as a triangle mesh (outward faces counter-clockwise, smooth normals).
    func mesh(cellSize: Float = Self.cellSize) -> Mesh {
        let margin = SIMD3<Float>(repeating: 2 * cellSize)
        let box = bounds
        let origin = box.lower - margin
        let extent = (box.upper + margin - origin) / cellSize
        let counts = SIMD3(Int(extent.x.rounded(.up)) + 1, Int(extent.y.rounded(.up)) + 1, Int(extent.z.rounded(.up)) + 1)
        let grid = Grid(origin: origin, cellSize: cellSize, counts: counts)
        let values = sample(grid)
        var mesh = Mesh()
        let vertices = placeVertices(grid: grid, values: values, mesh: &mesh)
        connect(grid: grid, values: values, vertices: vertices, mesh: &mesh)
        return mesh
    }

    /// The sampling grid: `counts` points per axis from `origin`, `cellSize` apart.
    private struct Grid {
        let origin: SIMD3<Float>
        let cellSize: Float
        let counts: SIMD3<Int>

        func point(_ x: Int, _ y: Int, _ z: Int) -> Int { x + counts.x * (y + counts.y * z) }
        func cell(_ x: Int, _ y: Int, _ z: Int) -> Int { x + (counts.x - 1) * (y + (counts.y - 1) * z) }
        func position(_ x: Int, _ y: Int, _ z: Int) -> SIMD3<Float> {
            origin + SIMD3(Float(x), Float(y), Float(z)) * cellSize
        }
    }

    /// Points per side of the blocks the grid is sampled in.
    private static let block = 4

    /// The field at every grid point, block by block: a block far from the skin (its centre farther than the block's
    /// half-diagonal plus two steps) takes its centre's value everywhere. Its points then have the right sign but not
    /// their exact distance, which only the cells the skin crosses use, and none of them touches such a block: the
    /// field changes by at most one step per step. Most of the box is far from the hand: ~5 times fewer evaluations.
    private func sample(_ grid: Grid) -> [Float] {
        let counts = grid.counts
        var values = [Float](repeating: 0, count: counts.x * counts.y * counts.z)
        let size = Self.block
        let reach = (Float(size - 1) / 2 * Float(3).squareRoot() + 2) * grid.cellSize
        for blockZ in stride(from: 0, to: counts.z, by: size) {
            for blockY in stride(from: 0, to: counts.y, by: size) {
                for blockX in stride(from: 0, to: counts.x, by: size) {
                    let upper = SIMD3(min(blockX + size, counts.x), min(blockY + size, counts.y),
                                      min(blockZ + size, counts.z))
                    let centre = grid.origin
                        + (SIMD3<Float>(Float(blockX + upper.x - 1), Float(blockY + upper.y - 1),
                                        Float(blockZ + upper.z - 1)) / 2) * grid.cellSize
                    let far = distance(centre)
                    let isFar = abs(far) > reach
                    for z in blockZ..<upper.z {
                        for y in blockY..<upper.y {
                            for x in blockX..<upper.x {
                                values[grid.point(x, y, z)] = isFar ? far : distance(grid.position(x, y, z))
                            }
                        }
                    }
                }
            }
        }
        return values
    }

    /// A cube's 12 edges, as pairs of its corners (corner bits: 1 = +x, 2 = +y, 4 = +z).
    private static let cubeEdges: [(Int, Int)] = [
        (0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)
    ]

    /// One vertex in every cell the surface crosses; returns each cell's vertex index (−1: none).
    private func placeVertices(grid: Grid, values: [Float], mesh: inout Mesh) -> [Int32] {
        let counts = grid.counts
        var vertices = [Int32](repeating: -1, count: (counts.x - 1) * (counts.y - 1) * (counts.z - 1))
        var corners = [Float](repeating: 0, count: 8)
        for z in 0..<(counts.z - 1) {
            for y in 0..<(counts.y - 1) {
                for x in 0..<(counts.x - 1) {
                    var inside = 0
                    for corner in 0..<8 {
                        let value = values[grid.point(x + corner & 1, y + (corner >> 1) & 1, z + (corner >> 2) & 1)]
                        corners[corner] = value
                        if value < 0 { inside += 1 }
                    }
                    guard inside > 0 && inside < 8 else { continue }
                    var sum = SIMD3<Float>.zero
                    var crossings: Float = 0
                    for (first, second) in Self.cubeEdges where (corners[first] < 0) != (corners[second] < 0) {
                        let along = corners[first] / (corners[first] - corners[second])
                        let start = Self.cornerOffset(first)
                        sum += start + (Self.cornerOffset(second) - start) * along
                        crossings += 1
                    }
                    var position = grid.position(x, y, z) + sum / crossings * grid.cellSize
                    let normal = normal(at: position)
                    // Onto the surface: one step along the gradient (whose direction barely changes on the way).
                    position -= normal * distance(position)
                    vertices[grid.cell(x, y, z)] = Int32(mesh.positions.count)
                    mesh.positions.append(position)
                    mesh.normals.append(normal)
                }
            }
        }
        return vertices
    }

    private static func cornerOffset(_ corner: Int) -> SIMD3<Float> {
        SIMD3(Float(corner & 1), Float((corner >> 1) & 1), Float((corner >> 2) & 1))
    }

    /// One quad for every grid edge the surface crosses, joining the vertices of the four cells around it, facing
    /// out of the hand.
    private func connect(grid: Grid, values: [Float], vertices: [Int32], mesh: inout Mesh) {
        let counts = grid.counts
        for z in 0..<counts.z {
            for y in 0..<counts.y {
                for x in 0..<counts.x {
                    let inside = values[grid.point(x, y, z)] < 0
                    // Along +x: the cells around it, counter-clockwise seen from +x (y, then z).
                    if x < counts.x - 1, y > 0, z > 0, y < counts.y - 1, z < counts.z - 1,
                       inside != (values[grid.point(x + 1, y, z)] < 0) {
                        quad([grid.cell(x, y - 1, z - 1), grid.cell(x, y, z - 1), grid.cell(x, y, z),
                              grid.cell(x, y - 1, z)], facingAxis: inside, vertices: vertices, mesh: &mesh)
                    }
                    // Along +y: counter-clockwise seen from +y (z, then x).
                    if y < counts.y - 1, x > 0, z > 0, x < counts.x - 1, z < counts.z - 1,
                       inside != (values[grid.point(x, y + 1, z)] < 0) {
                        quad([grid.cell(x - 1, y, z - 1), grid.cell(x - 1, y, z), grid.cell(x, y, z),
                              grid.cell(x, y, z - 1)], facingAxis: inside, vertices: vertices, mesh: &mesh)
                    }
                    // Along +z: counter-clockwise seen from +z (x, then y).
                    if z < counts.z - 1, x > 0, y > 0, x < counts.x - 1, y < counts.y - 1,
                       inside != (values[grid.point(x, y, z + 1)] < 0) {
                        quad([grid.cell(x - 1, y - 1, z), grid.cell(x, y - 1, z), grid.cell(x, y, z),
                              grid.cell(x - 1, y, z)], facingAxis: inside, vertices: vertices, mesh: &mesh)
                    }
                }
            }
        }
    }

    /// Two triangles; `facingAxis`: the outside is along the edge's axis (else the quad is turned over).
    private func quad(_ cells: [Int], facingAxis: Bool, vertices: [Int32], mesh: inout Mesh) {
        let corners = cells.map { vertices[$0] }
        guard !corners.contains(-1) else { return }
        let order = facingAxis ? [0, 1, 2, 0, 2, 3] : [0, 2, 1, 0, 3, 2]
        mesh.indices += order.map { UInt32(corners[$0]) }
    }
}
