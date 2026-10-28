import simd
import Testing
@testable import Macrowavers

struct RideShapesTests {
    /// Every index points at a vertex, every vertex has a unit normal.
    private func expectWellFormed(_ mesh: RideShapes.Mesh) {
        #expect(!mesh.indices.isEmpty)
        #expect(mesh.indices.count % 3 == 0)
        #expect(mesh.positions.count == mesh.normals.count)
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count })
        #expect(mesh.normals.allSatisfy { abs(simd_length($0) - 1) < 0.001 })
    }

    @Test func theLanternIsAClosedFacetedOutlineFacingOutwards() {
        let lantern = RideShapes.lantern(sides: 8)
        expectWellFormed(lantern)
        let heights = lantern.positions.map(\.y)
        #expect(abs((heights.max() ?? 0) - (heights.min() ?? 0) - 1.11) < 0.001)
        for (position, normal) in zip(lantern.positions, lantern.normals) where simd_length(SIMD2(position.x, position.z)) > 0.05 {
            #expect(simd_dot(SIMD2(normal.x, normal.z), SIMD2(position.x, position.z)) > -0.001)
        }
    }

    @Test func aSpeckIsALowPolyBallFacingOutwards() {
        let speck = RideShapes.speck()
        expectWellFormed(speck)
        #expect(speck.indices.count / 3 == 20)
        #expect(speck.positions.allSatisfy { abs(simd_length($0) - 1) < 0.001 })
        // Counter-clockwise seen from outside: RealityKit draws its front faces.
        for face in stride(from: 0, to: speck.indices.count, by: 3) {
            let corners = (0..<3).map { speck.positions[Int(speck.indices[face + $0])] }
            let normal = simd_cross(corners[1] - corners[0], corners[2] - corners[0])
            #expect(simd_dot(normal, corners.reduce(.zero, +)) > 0)
        }
    }

    @Test func aMountainFacesOutwards() {
        // Its material culls the back faces: every face that is not a sliver at a peak is counter-clockwise seen
        // from outside.
        var random = SeededRandom(seed: 2)
        let mountain = RideShapes.mountain(height: 100, using: &random)
        for face in stride(from: 0, to: mountain.indices.count, by: 3) {
            let corners = (0..<3).map { Int(mountain.indices[face + $0]) }
            let normal = simd_cross(mountain.positions[corners[1]] - mountain.positions[corners[0]],
                                    mountain.positions[corners[2]] - mountain.positions[corners[0]])
            guard simd_length(normal) > 1e-3 else { continue }
            #expect(simd_dot(normal, corners.map { mountain.normals[$0] }.reduce(.zero, +)) > 0)
        }
    }

    @Test func aMountainRisesFromItsBaseToARoundTop() {
        var random = SeededRandom(seed: 2)
        let mountain = RideShapes.mountain(height: 100, using: &random)
        expectWellFormed(mountain)
        let top = mountain.positions.max { $0.y < $1.y }
        #expect(abs((top?.y ?? 0) - 100) < 0.001)
        #expect(mountain.positions.allSatisfy { $0.y >= 0 })
        // The top's normal points up.
        let spire = RideShapes.spire(height: 50, radius: 10)
        let index = spire.positions.indices.max { spire.positions[$0].y < spire.positions[$1].y } ?? 0
        #expect(spire.normals[index].y > 0.9)
    }
}
