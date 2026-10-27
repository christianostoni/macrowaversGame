import simd

/// Chapter II's constellation: a shamseh, the sun-like star medallion of Persian tilework (the girih of Isfahan's
/// tiled domes), drawn faintly across the sky. Every fruit the dragon eats gives one of its petals that fruit's
/// colour; once they all have one, its central star lights up.
/// Pure geometry and state, no RealityKit, in a unit disc (y up): `DragonRideSystem` draws it far away in the sky.
struct Shamseh {
    /// A tile of the medallion. Its corners go counter-clockwise and the tile is star-shaped from `centre`: a fan of
    /// triangles from there fills it.
    struct Shape {
        let centre: SIMD2<Float>
        let corners: [SIMD2<Float>]
    }

    /// Flat triangles (counter-clockwise, seen from +z).
    struct Mesh {
        var positions: [SIMD2<Float>] = []
        var indices: [UInt32] = []
    }

    enum Settings {
        /// The central star: its points and the notches between them.
        static let starTip: Float = 0.34
        static let starNotch: Float = 0.2
        /// The petals between the star's points: where their sides bend, how far apart (a share of the half-angle
        /// between two points) and where their tips reach.
        static let petalSide: Float = 0.6
        static let petalSideSpread: Float = 0.62
        static let petalTip: Float = 0.86
        /// The kites between the petals reach the medallion's rim.
        static let rim: Float = 1
        /// Segments of the rim's circle per fold.
        static let rimSegments = 8
        /// Around the rim, like an astrolabe's: rays (long from the star's points, short between them), each ending
        /// in a small orb, and a ring of dots.
        static let longRay: Float = 1.42
        static let shortRay: Float = 1.2
        static let orbRadius: Float = 0.024
        static let dotRing: Float = 1.1
        static let dotsPerFold = 6
        static let dotRadius: Float = 0.007
    }

    /// Petals around the star (one per fruit).
    let folds: Int
    let star: Shape
    /// Petal `i` sits between the star's points `i` and `i + 1`.
    let petals: [Shape]
    /// Kite `i` sits at the star's point `i`, between petals `i - 1` and `i`.
    let kites: [Shape]
    /// The strapwork: every edge of the tiles, once, the rim, and a ray from each petal's tip to it.
    let strands: [(SIMD2<Float>, SIMD2<Float>)]
    /// Rays out from the rim, the orbs at their ends and the ring of dots around it.
    let rays: [(SIMD2<Float>, SIMD2<Float>)]
    let orbs: [SIMD2<Float>]
    let dots: [SIMD2<Float>]
    /// The fruit that gave the petals their colours, in order.
    private(set) var colours: [FruitKind] = []

    var isComplete: Bool { colours.count >= folds }

    init(folds: Int) {
        self.folds = folds
        let step = 2 * Float.pi / Float(folds)
        let spread = Settings.petalSideSpread * step / 2
        func point(_ radius: Float, _ angle: Float) -> SIMD2<Float> { radius * SIMD2(cos(angle), sin(angle)) }

        star = Shape(centre: .zero, corners: (0..<folds).flatMap { index in
            let angle = Float(index) * step
            return [point(Settings.starTip, angle), point(Settings.starNotch, angle + step / 2)]
        })
        petals = (0..<folds).map { index in
            let middle = (Float(index) + 0.5) * step
            let corners = [point(Settings.starNotch, middle), point(Settings.starTip, middle - step / 2),
                           point(Settings.petalSide, middle - spread), point(Settings.petalTip, middle),
                           point(Settings.petalSide, middle + spread), point(Settings.starTip, middle + step / 2)]
            return Shape(centre: corners.reduce(.zero, +) / Float(corners.count), corners: corners)
        }
        kites = (0..<folds).map { index in
            let angle = Float(index) * step
            let corners = [point(Settings.starTip, angle), point(Settings.petalSide, angle - step / 2 + spread),
                           point(Settings.rim, angle), point(Settings.petalSide, angle + step / 2 - spread)]
            return Shape(centre: corners.reduce(.zero, +) / Float(corners.count), corners: corners)
        }

        var strands: [(SIMD2<Float>, SIMD2<Float>)] = []
        var seen: Set<[Int32]> = []
        func add(_ start: SIMD2<Float>, _ end: SIMD2<Float>) {
            // Shared edges are drawn once: the same two ends, rounded, in either order.
            let ends = [start, end].map { SIMD2<Int32>(($0 * 1000).rounded(.toNearestOrAwayFromZero)) }
                .sorted { ($0.x, $0.y) < ($1.x, $1.y) }
            guard seen.insert([ends[0].x, ends[0].y, ends[1].x, ends[1].y]).inserted else { return }
            strands.append((start, end))
        }
        for shape in [star] + petals + kites {
            for (index, corner) in shape.corners.enumerated() {
                add(corner, shape.corners[(index + 1) % shape.corners.count])
            }
        }
        for index in 0..<folds {
            let middle = (Float(index) + 0.5) * step
            add(point(Settings.petalTip, middle), point(Settings.rim, middle))
        }
        let segments = folds * Settings.rimSegments
        for index in 0..<segments {
            let angle = 2 * Float.pi / Float(segments)
            add(point(Settings.rim, Float(index) * angle), point(Settings.rim, Float(index + 1) * angle))
        }
        self.strands = strands

        rays = (0..<(2 * folds)).map { index in
            let angle = Float(index) * step / 2
            return (point(Settings.rim, angle), point(index.isMultiple(of: 2) ? Settings.longRay : Settings.shortRay,
                                                      angle))
        }
        orbs = rays.map(\.1)
        let dotCount = folds * Settings.dotsPerFold
        dots = (0..<dotCount).map { index in
            // Between the rays, never on them.
            point(Settings.dotRing, (Float(index) + 0.5) * 2 * .pi / Float(dotCount))
        }
    }

    /// The next petal takes `fruit`'s colour. Bananas give none, nor fruit once every petal has one.
    mutating func colour(with fruit: FruitKind) {
        guard !isComplete, fruit.isLikedByDragon else { return }
        colours.append(fruit)
    }

    /// The last `count` petals lose their colour (the dragon, exhausted, starts its wave over).
    mutating func uncolour(last count: Int) {
        colours.removeLast(min(max(count, 0), colours.count))
    }

    /// `shape` filled, around its centre (the tiles light up and pop about it).
    func fill(_ shape: Shape) -> Mesh {
        var mesh = Mesh(positions: [.zero] + shape.corners.map { $0 - shape.centre })
        let count = UInt32(shape.corners.count)
        for index in 0..<count {
            mesh.indices += [0, 1 + index, 1 + (index + 1) % count]
        }
        return mesh
    }

    /// The strapwork as bands `width` wide, a little longer than the strands so they meet at the corners.
    func strapwork(width: Float) -> Mesh {
        Self.bands(strands, width: width)
    }

    /// The rays as bands `width` wide, the orbs at their ends and the dots.
    func ornaments(width: Float) -> Mesh {
        var mesh = Self.bands(rays, width: width)
        for (centre, radius) in orbs.map({ ($0, Settings.orbRadius) }) + dots.map({ ($0, Settings.dotRadius) }) {
            let first = UInt32(mesh.positions.count)
            let sides: UInt32 = 12
            mesh.positions.append(centre)
            for side in 0..<sides {
                let angle = Float(side) / Float(sides) * 2 * .pi
                mesh.positions.append(centre + radius * SIMD2(cos(angle), sin(angle)))
                mesh.indices += [first, first + 1 + side, first + 1 + (side + 1) % sides]
            }
        }
        return mesh
    }

    private static func bands(_ lines: [(SIMD2<Float>, SIMD2<Float>)], width: Float) -> Mesh {
        var mesh = Mesh()
        for (start, end) in lines {
            let along = simd_normalize(end - start)
            let across = SIMD2(-along.y, along.x) * width / 2
            let from = start - along * width / 2
            let to = end + along * width / 2
            let first = UInt32(mesh.positions.count)
            mesh.positions += [from - across, to - across, to + across, from + across]
            mesh.indices += [first, first + 1, first + 2, first, first + 2, first + 3]
        }
        return mesh
    }
}
