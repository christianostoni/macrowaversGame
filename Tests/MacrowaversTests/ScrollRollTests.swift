import simd
import Testing
@testable import Macrowavers

/// The scroll's paper (`ScrollRoll`): however it is rolled it keeps its length, its rolls are spirals around their
/// rods in front of the window, and the window goes from the page's top to its end.
struct ScrollRollTests {
    private let roll = ScrollRoll(width: 0.45, pageLength: 1.45)

    private var poses: [ScrollRoll.Pose] {
        [(0, 0), (0.5, 0), (1, 0), (1, 0.5), (1, 1), (0.3, 1)].map { roll.pose(open: $0.0, scroll: $0.1) }
    }

    @Test func thePaperKeepsItsLength() {
        let rows = roll.rows()
        for pose in poses {
            let length = zip(rows, rows.dropFirst()).reduce(Float(0)) { sum, pair in
                sum + simd_distance(roll.point(at: pair.0, pose: pose), roll.point(at: pair.1, pose: pose))
            }
            // The rolls' facets are chords of the spiral: a little shorter than the paper.
            #expect(abs(length - roll.length) < roll.length * 0.02, "\(pose): \(length) m of paper, \(roll.length) m")
        }
    }

    @Test func theWindowGoesFromThePagesTopToItsEnd() {
        let start = roll.pose(open: 1, scroll: 0), end = roll.pose(open: 1, scroll: 1)
        #expect(abs(start.window - roll.openWindow) < 1e-5)
        #expect(abs(start.top - roll.lead) < 1e-5)
        #expect(abs(end.top + end.window - (roll.length - roll.lead)) < 1e-5)
        for pose in [start, end] {
            // The window's top edge stays put; its paper hangs straight down, with a small wave.
            #expect(simd_length(roll.point(at: pose.top, pose: pose)) < 1e-5)
            let bottom = roll.point(at: pose.top + pose.window, pose: pose)
            #expect(abs(bottom.x + pose.window) < 1e-5 && abs(bottom.y) < 1e-5)
            for step in 0...20 {
                let point = roll.point(at: pose.top + pose.window * Float(step) / 20, pose: pose)
                #expect(abs(point.y) <= roll.wave * pose.window)
            }
        }
    }

    @Test func eachRollIsASpiralAroundItsRodInFrontOfTheWindow() {
        for pose in poses {
            let rods = roll.rods(pose), rolled = roll.rolled(pose)
            let bottomEdge = pose.top + pose.window
            let rolls = [(rods.top, stride(from: pose.top, through: 0, by: -0.002).map { $0 }, rolled.top),
                         (rods.bottom, stride(from: bottomEdge, through: roll.length, by: 0.002).map { $0 }, rolled.bottom)]
            for (rod, rows, paper) in rolls {
                // From the window's edge inwards, ever closer to the rod, never inside the core.
                let distances = rows.map { simd_distance(roll.point(at: $0, pose: pose), rod) }
                #expect(abs((distances.first ?? 0) - roll.radius(rolled: paper)) < 1e-4)
                #expect(zip(distances, distances.dropFirst()).allSatisfy { $1 <= $0 + 1e-5 })
                #expect((distances.min() ?? 0) >= roll.coreRadius - 1e-4)
                #expect(rows.allSatisfy { roll.point(at: $0, pose: pose).y >= -1e-5 })
            }
        }
    }

    @Test func theClosedRollsTouchWithoutCrossing() {
        let closed = roll.pose(open: 0, scroll: 0)
        let rods = roll.rods(closed), rolled = roll.rolled(closed)
        let gap = simd_distance(rods.top, rods.bottom) - roll.radius(rolled: rolled.top) - roll.radius(rolled: rolled.bottom)
        #expect(gap > 0 && gap < 0.01, "gap \(gap) m")
    }

    @Test func thePageLiesBetweenTheLeadsTheRightWayUp() throws {
        let mesh = roll.mesh(pose: roll.pose(open: 1, scroll: 0))
        let top = try #require(mesh.rows.firstIndex(of: roll.lead))
        let end = try #require(mesh.rows.firstIndex(of: roll.length - roll.lead))
        #expect(mesh.uvs[2 * top] == SIMD2(0, 1) && mesh.uvs[2 * top + 1] == SIMD2(1, 1))
        #expect(mesh.uvs[2 * end] == SIMD2(0, 0))
        #expect(mesh.positions.count == 2 * mesh.rows.count + 4 * (mesh.rows.count - 1))
        #expect(mesh.uvs.count == mesh.positions.count && mesh.normals.count == mesh.positions.count)
        #expect(mesh.indices.count == 2 * 6 * (mesh.rows.count - 1))
        #expect(ScrollRoll.MeshPart.allCases.allSatisfy { !(mesh.parts[$0]?.isEmpty ?? true) })
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count })
    }

    /// Front and back: every triangle faces the way its vertices' normal says (the front to the reader in the window).
    @Test func everyFaceTurnsItsSide() {
        let mesh = roll.mesh(pose: roll.pose(open: 1, scroll: 0.5))
        for first in stride(from: 0, to: mesh.indices.count, by: 3) {
            let corners = (0..<3).map { Int(mesh.indices[first + $0]) }
            let face = simd_cross(mesh.positions[corners[1]] - mesh.positions[corners[0]],
                                  mesh.positions[corners[2]] - mesh.positions[corners[0]])
            guard simd_length(face) > 1e-10 else { continue }
            #expect(simd_dot(face, mesh.normals[corners[0]]) > 0, "triangle \(first / 3)")
        }
        let middle = mesh.rows.count / 2
        #expect(simd_dot(mesh.normals[2 * middle], SIMD3(0, 0, 1)) > 0.9)
    }
}
