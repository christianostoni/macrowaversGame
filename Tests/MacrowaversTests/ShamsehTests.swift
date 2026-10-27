import simd
import Testing
@testable import Macrowavers

struct ShamsehTests {
    /// Twice the signed area of the triangle: positive when it turns counter-clockwise.
    private func turn(_ first: SIMD2<Float>, _ second: SIMD2<Float>, _ third: SIMD2<Float>) -> Float {
        let out = second - first
        let on = third - second
        return out.x * on.y - out.y * on.x
    }

    @Test(arguments: [8, 10])
    func theTilesFitInTheMedallionAndFillWithoutFolding(folds: Int) {
        let shamseh = Shamseh(folds: folds)
        #expect(shamseh.petals.count == folds)
        #expect(shamseh.kites.count == folds)
        #expect(shamseh.star.corners.count == 2 * folds)
        // Petals and kites are convex; every tile's fan turns counter-clockwise (faces the player).
        for shape in shamseh.petals + shamseh.kites {
            let corners = shape.corners
            for index in corners.indices {
                #expect(turn(corners[index], corners[(index + 1) % corners.count],
                             corners[(index + 2) % corners.count]) > 0)
            }
        }
        for shape in [shamseh.star] + shamseh.petals + shamseh.kites {
            #expect(shape.corners.allSatisfy { simd_length($0) <= Shamseh.Settings.rim + 0.001 })
            let mesh = shamseh.fill(shape)
            #expect(mesh.indices.count == 3 * shape.corners.count)
            for triangle in stride(from: 0, to: mesh.indices.count, by: 3) {
                let points = (0..<3).map { mesh.positions[Int(mesh.indices[triangle + $0])] }
                #expect(turn(points[0], points[1], points[2]) > 0)
            }
        }
    }

    @Test func sharedEdgesAreDrawnOnce() {
        let shamseh = Shamseh(folds: 8)
        let keys = shamseh.strands.map { start, end in
            [start, end].map { SIMD2<Int32>(($0 * 1000).rounded(.toNearestOrAwayFromZero)) }
                .sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        }
        #expect(Set(keys.map { [$0[0].x, $0[0].y, $0[1].x, $0[1].y] }).count == keys.count)
        // Star (16 edges), petals (4 own edges each), kites (2 own edges each), rays (8), rim (64).
        #expect(shamseh.strands.count == 16 + 8 * 4 + 8 * 2 + 8 + 64)
        #expect(shamseh.strapwork(width: 0.01).indices.count == 6 * shamseh.strands.count)
    }

    @Test func raysOrbsAndDotsCircleTheRim() {
        let shamseh = Shamseh(folds: 8)
        #expect(shamseh.rays.count == 16 && shamseh.orbs.count == 16)
        #expect(shamseh.dots.count == 8 * Shamseh.Settings.dotsPerFold)
        // The long rays start from the star's points (index 0 at angle 0).
        #expect(abs(simd_length(shamseh.orbs[0]) - Shamseh.Settings.longRay) < 0.001)
        #expect(abs(simd_length(shamseh.orbs[1]) - Shamseh.Settings.shortRay) < 0.001)
        let mesh = shamseh.ornaments(width: 0.004)
        #expect(mesh.indices.count == 6 * 16 + 3 * 12 * (16 + shamseh.dots.count))
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count })
    }

    @Test func eachFruitTheDragonEatsColoursAPetalButBananas() {
        var shamseh = Shamseh(folds: 3)
        shamseh.colour(with: .pomegranate)
        shamseh.colour(with: .banana)
        shamseh.colour(with: .orange)
        #expect(shamseh.colours == [.pomegranate, .orange])
        #expect(!shamseh.isComplete)
        shamseh.colour(with: .apple)
        shamseh.colour(with: .pineapple)
        #expect(shamseh.colours == [.pomegranate, .orange, .apple])
        #expect(shamseh.isComplete)
    }
}
