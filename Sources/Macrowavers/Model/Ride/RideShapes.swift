import Foundation
import simd

/// The shapes chapter II's sky is built from, in code: Persian lanterns, the mountain peaks far below and the
/// clouds flown past. Pure
/// geometry (metres, y up), no RealityKit; `RideScenery` makes meshes of them and gives them the airbrush material,
/// which shades by the normals (facing the player dark, rims light).
enum RideShapes {
    struct Mesh {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        /// Adds `other`, moved by `offset`.
        mutating func append(_ other: Mesh, offset: SIMD3<Float> = .zero) {
            let first = UInt32(positions.count)
            positions += other.positions.map { $0 + offset }
            normals += other.normals
            indices += other.indices.map { $0 + first }
        }
    }

    // MARK: - Lantern

    /// A Persian lantern's outline (radius, height; m, 1.1 m tall): a finial below, a cup, the bulging body, a
    /// collar and an onion dome with its spike.
    static let lanternProfile: [SIMD2<Float>] = [
        SIMD2(0, -0.55), SIMD2(0.05, -0.5), SIMD2(0.03, -0.45), SIMD2(0.12, -0.4), SIMD2(0.2, -0.32),
        SIMD2(0.3, -0.2), SIMD2(0.33, -0.02), SIMD2(0.29, 0.12), SIMD2(0.16, 0.18), SIMD2(0.21, 0.22),
        SIMD2(0.28, 0.27), SIMD2(0.26, 0.35), SIMD2(0.17, 0.42), SIMD2(0.07, 0.47), SIMD2(0.02, 0.5),
        SIMD2(0, 0.56),
    ]

    /// The lantern, low-poly like the island's tree: `sides` flat facets around.
    static func lantern(sides: Int = 8) -> Mesh {
        var mesh = Mesh()
        let profile = lanternProfile
        for ring in 0..<(profile.count - 1) {
            for side in 0..<sides {
                let corners = [(ring, side), (ring, side + 1), (ring + 1, side + 1), (ring + 1, side)].map {
                    lathePoint(profile[$0.0], angle: Float($0.1) / Float(sides) * 2 * .pi)
                }
                // The diagonals' cross product: sound even where a ring shrinks to a point.
                var normal = simd_cross(corners[2] - corners[0], corners[3] - corners[1])
                let centre = corners.reduce(.zero, +) / 4
                if simd_dot(normal, centre - SIMD3(0, centre.y, 0)) < 0 { normal = -normal }
                guard simd_length(normal) > 1e-9 else { continue }
                normal = simd_normalize(normal)
                let first = UInt32(mesh.positions.count)
                mesh.positions += corners
                mesh.normals += Array(repeating: normal, count: 4)
                mesh.indices += [first, first + 1, first + 2, first, first + 2, first + 3]
            }
        }
        return mesh
    }

    // MARK: - Specks

    /// A speck of air: an icosahedron of radius 1, 20 faces. The specks are a few centimetres across, metres away:
    /// round enough as dots, where a generated sphere costs ~8,000 triangles each (160 of them: ~1.3 M a frame).
    /// Counter-clockwise seen from outside (RealityKit's front faces).
    static func speck() -> Mesh {
        let golden = (1 + Float(5).squareRoot()) / 2
        let corners = [
            SIMD3<Float>(-1, golden, 0), SIMD3(1, golden, 0), SIMD3(-1, -golden, 0), SIMD3(1, -golden, 0),
            SIMD3(0, -1, golden), SIMD3(0, 1, golden), SIMD3(0, -1, -golden), SIMD3(0, 1, -golden),
            SIMD3(golden, 0, -1), SIMD3(golden, 0, 1), SIMD3(-golden, 0, -1), SIMD3(-golden, 0, 1),
        ].map(simd_normalize)
        let faces: [UInt32] = [
            0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
            3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
        ]
        return Mesh(positions: corners, normals: corners, indices: faces)
    }

    // MARK: - Mountains

    /// A round-topped peak, `height` tall from its base at the origin, `radius` wide there: smooth, like the
    /// mountains of Persian and Chinese paintings, rising straight and rounding off at the top.
    static func spire(height: Float, radius: Float, sides: Int = 14, rings: Int = 14) -> Mesh {
        var mesh = Mesh()
        // Rings closer together near the top, where it rounds off.
        let heights = (0...rings).map { height * (1 - pow(1 - Float($0) / Float(rings), 1.6)) }
        for y in heights {
            let rise = min(y / height, 1)
            let shape = 1 - pow(rise, 2.6)
            let ringRadius = radius * pow(max(shape, 0), 0.55)
            // The slope of the outline (dr/dy) tilts the normals up.
            let slope = radius * 0.55 * pow(max(shape, 1e-4), -0.45) * -2.6 * pow(rise, 1.6) / height
            for side in 0...sides {
                let angle = Float(side) / Float(sides) * 2 * .pi
                let around = SIMD3(cos(angle), 0, sin(angle))
                mesh.positions.append(around * ringRadius + SIMD3(0, y, 0))
                mesh.normals.append(simd_normalize(around + SIMD3(0, -max(slope, -50), 0)))
            }
        }
        let row = UInt32(sides + 1)
        for ring in 0..<UInt32(rings) {
            for side in 0..<UInt32(sides) {
                let corner = ring * row + side
                mesh.indices += [corner, corner + row, corner + 1, corner + 1, corner + row, corner + row + 1]
            }
        }
        return mesh
    }

    /// A mountain: a tall peak with smaller ones crowding around and in front of it. Its base is at the origin; its
    /// top `height` above.
    static func mountain(height: Float, using random: inout some RandomNumberGenerator) -> Mesh {
        var mesh = Mesh()
        let radius = height * Float.random(in: 0.18...0.24, using: &random)
        mesh.append(spire(height: height, radius: radius))
        for _ in 0..<Int.random(in: 4...7, using: &random) {
            let share = Float.random(in: 0.3...0.75, using: &random)
            let angle = Float.random(in: 0..<(2 * .pi), using: &random)
            let offset = SIMD3(cos(angle), 0, sin(angle)) * radius * Float.random(in: 0.7...1.6, using: &random)
            mesh.append(spire(height: height * share, radius: radius * Float.random(in: 0.5...0.85, using: &random),
                              sides: 12, rings: 10),
                        offset: offset)
        }
        return mesh
    }
    // MARK: - Clouds

    /// The clouds' two shapes, both like a drawing's cloud (round bumps on top, a flat bottom), so they don't all
    /// look alike: a heap (one big bump in the middle) and a puff (two big bumps side by side).
    enum CloudShape: CaseIterable {
        case heap, puff
    }

    /// A cloud, clean and smooth like the mountains (about one unit long, centred, its flat faces towards ±z): round
    /// bumps over a row of smaller ones that make its flat bottom, melted into one closed surface (one mesh, nothing
    /// inside it: see-through, no bump shows through another). Each one its own: the bumps vary, `mirrored` flips
    /// it.
    static func cloud(_ shape: CloudShape, mirrored: Bool = false,
                      using random: inout some RandomNumberGenerator) -> Mesh {
        func vary(_ value: Float, by amount: Float = 0.02) -> Float {
            value + Float.random(in: -amount...amount, using: &random)
        }
        // How flat the bumps are (their depth over their height), and how softly they melt together.
        let flatness: Float = 0.42
        let melt: Float = 0.05

        // (x, y, radius): the bumps on top, then the row along the bottom.
        let layout: [SIMD3<Float>] = switch shape {
        case .heap:
            [SIMD3(-0.02, 0.28, 0.22), SIMD3(-0.25, 0.17, 0.15), SIMD3(0.24, 0.16, 0.14),
             SIMD3(-0.38, 0.09, 0.09), SIMD3(-0.12, 0.1, 0.12), SIMD3(0.13, 0.1, 0.12), SIMD3(0.38, 0.09, 0.09)]
        case .puff:
            [SIMD3(-0.13, 0.26, 0.19), SIMD3(0.14, 0.3, 0.2), SIMD3(-0.33, 0.15, 0.12), SIMD3(0.36, 0.15, 0.11),
             SIMD3(-0.2, 0.1, 0.12), SIMD3(0.05, 0.09, 0.13), SIMD3(0.26, 0.1, 0.11)]
        }
        let sign: Float = mirrored ? -1 : 1
        let bumps = layout.map { bump in
            let radius = vary(bump.z, by: 0.015)
            return (centre: SIMD3(sign * vary(bump.x), vary(bump.y, by: 0.015), 0),
                    radii: SIMD3(radius, radius, radius * flatness))
        }
        // Negative inside: the bumps (ellipsoids, about their distance) melted together.
        func field(_ point: SIMD3<Float>) -> Float {
            bumps.reduce(Float.infinity) { inside, bump in
                let distance = (simd_length((point - bump.centre) / bump.radii) - 1) * bump.radii.min()
                return smoothMinimum(inside, distance, melt)
            }
        }
        var mesh = implicitSurface(from: SIMD3(-0.6, -0.08, -0.16), to: SIMD3(0.6, 0.62, 0.16), cell: 0.022,
                                   field: field)

        // Centred on its bounds, so its distance from the player is from its middle.
        let low = mesh.positions.reduce(SIMD3(repeating: .infinity)) { simd_min($0, $1) }
        let high = mesh.positions.reduce(SIMD3(repeating: -.infinity)) { simd_max($0, $1) }
        let middle = (low + high) / 2
        mesh.positions = mesh.positions.map { $0 - middle }
        return mesh
    }

    /// The smooth minimum of `first` and `second`: two shapes melted together over `width`.
    private static func smoothMinimum(_ first: Float, _ second: Float, _ width: Float) -> Float {
        guard first.isFinite else { return second }
        let blend = max(width - abs(first - second), 0) / width
        return min(first, second) - blend * blend * width / 4
    }

    /// The surface where `field` is 0 (negative inside) between `start` and `end`, sampled every `cell` (surface
    /// nets: a vertex in each cell the surface crosses, at the middle of its crossings, faces between them). One
    /// closed mesh, its normals the field's gradient, wound counter-clockwise seen from outside.
    static func implicitSurface(from start: SIMD3<Float>, to end: SIMD3<Float>, cell: Float,
                                field: (SIMD3<Float>) -> Float) -> Mesh {
        var grid = SurfaceGrid(from: start, to: end, cell: cell, field: field)
        grid.placeVertices(field: field)
        grid.connectFaces()
        return grid.mesh
    }
}

/// The samples of a field on a grid and the surface nets mesh made from them (`RideShapes.implicitSurface`).
private struct SurfaceGrid {
    let start: SIMD3<Float>
    let cell: Float
    let counts: SIMD3<Int>
    var values: [Float]
    var mesh = RideShapes.Mesh()
    /// The vertex in each cell the surface crosses, by the cell's index.
    var vertexOfCell: [Int: UInt32] = [:]

    static let corners = (0..<8).map { SIMD3($0 & 1, ($0 >> 1) & 1, ($0 >> 2) & 1) }
    static let edges = [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)]

    init(from start: SIMD3<Float>, to end: SIMD3<Float>, cell: Float, field: (SIMD3<Float>) -> Float) {
        self.start = start
        self.cell = cell
        counts = SIMD3<Int>(((end - start) / cell).rounded(.up)) &+ 1
        values = [Float](repeating: 0, count: counts.x * counts.y * counts.z)
        for z in 0..<counts.z {
            for y in 0..<counts.y {
                for x in 0..<counts.x { values[index(SIMD3(x, y, z))] = field(point(SIMD3(x, y, z))) }
            }
        }
    }

    func index(_ node: SIMD3<Int>) -> Int { (node.z * counts.y + node.y) * counts.x + node.x }
    func point(_ node: SIMD3<Int>) -> SIMD3<Float> { start + SIMD3<Float>(node) * cell }
    func value(_ node: SIMD3<Int>) -> Float { values[index(node)] }

    /// A vertex in every cell the surface crosses.
    mutating func placeVertices(field: (SIMD3<Float>) -> Float) {
        for z in 0..<counts.z - 1 {
            for y in 0..<counts.y - 1 {
                for x in 0..<counts.x - 1 {
                    let node = SIMD3(x, y, z)
                    guard let position = crossing(at: node) else { continue }
                    vertexOfCell[index(node)] = UInt32(mesh.positions.count)
                    mesh.positions.append(position)
                    mesh.normals.append(Self.normal(at: position, step: cell * 0.5, field: field))
                }
            }
        }
    }

    /// The middle of the surface's crossings of the cell's edges; nil when it does not cross the cell.
    func crossing(at node: SIMD3<Int>) -> SIMD3<Float>? {
        let samples = Self.corners.map { value(node &+ $0) }
        guard samples.contains(where: { $0 < 0 }), samples.contains(where: { $0 >= 0 }) else { return nil }
        var sum = SIMD3<Float>.zero, crossings: Float = 0
        for (from, to) in Self.edges where (samples[from] < 0) != (samples[to] < 0) {
            let along = samples[from] / (samples[from] - samples[to])
            let low = point(node &+ Self.corners[from]), high = point(node &+ Self.corners[to])
            sum += low + (high - low) * along
            crossings += 1
        }
        return sum / crossings
    }

    /// The field's gradient at `position`, unit length: the surface's normal.
    static func normal(at position: SIMD3<Float>, step: Float, field: (SIMD3<Float>) -> Float) -> SIMD3<Float> {
        let gradient = SIMD3(
            field(position + SIMD3(step, 0, 0)) - field(position - SIMD3(step, 0, 0)),
            field(position + SIMD3(0, step, 0)) - field(position - SIMD3(0, step, 0)),
            field(position + SIMD3(0, 0, step)) - field(position - SIMD3(0, 0, step)))
        return simd_length(gradient) > 1e-9 ? simd_normalize(gradient) : SIMD3(0, 1, 0)
    }

    /// A face across every grid edge the surface crosses, between the four cells around it.
    mutating func connectFaces() {
        let axes = [SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)]
        for (axis, direction) in axes.enumerated() {
            let (across, up) = (axes[(axis + 1) % 3], axes[(axis + 2) % 3])
            for z in 1..<counts.z - 1 {
                for y in 1..<counts.y - 1 {
                    for x in 1..<counts.x - 1 {
                        let here = SIMD3(x, y, z), next = here &+ direction
                        guard next.x < counts.x, next.y < counts.y, next.z < counts.z,
                              (value(here) < 0) != (value(next) < 0) else { continue }
                        let quad = [here, here &- across, here &- across &- up, here &- up]
                            .compactMap { vertexOfCell[index($0)] }
                        if quad.count == 4 { addQuad(quad) }
                    }
                }
            }
        }
    }

    /// Two triangles, each wound to face where its vertices' normals point.
    mutating func addQuad(_ quad: [UInt32]) {
        for var triangle in [[quad[0], quad[1], quad[2]], [quad[0], quad[2], quad[3]]] {
            let points = triangle.map { mesh.positions[Int($0)] }
            let facing = simd_cross(points[1] - points[0], points[2] - points[0])
            let normal = triangle.map { mesh.normals[Int($0)] }.reduce(.zero, +)
            if simd_dot(facing, normal) < 0 { triangle.swapAt(1, 2) }
            mesh.indices += triangle
        }
    }
}

private func lathePoint(_ outline: SIMD2<Float>, angle: Float) -> SIMD3<Float> {
    SIMD3(outline.x * cos(angle), outline.y, outline.x * sin(angle))
}
