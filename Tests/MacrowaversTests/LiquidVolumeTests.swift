import Foundation
import simd
import Testing
@testable import Macrowavers

/// The flask's liquid at every level stays inside the glass (a round flask: a sphere), with its surface flat at the
/// level, and matches the full liquid when full.
struct LiquidVolumeTests {
    private static let radius: Float = 0.1
    /// The full liquid is cut a little above the sphere's middle, as in the designers' flask.
    private static let cut: Float = 0.015

    /// The full liquid's vertices: rings on the sphere below the cut, and its flat top. `up` is +Y, or +Z (Blender).
    private static func fullLiquid(zUp: Bool = false) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        let rings = 14
        for ring in 0...rings {
            let y = -radius + (radius + cut) * Float(ring) / Float(rings)
            let ringRadius = (radius * radius - y * y).squareRoot()
            for segment in 0..<32 {
                let angle = 2 * Float.pi * Float(segment) / 32
                points.append(SIMD3(ringRadius * cos(angle), y, ringRadius * sin(angle)))
            }
        }
        points.append(SIMD3(0, cut, 0))
        return zUp ? points.map { SIMD3($0.x, -$0.z, $0.y) } : points
    }

    @Test(arguments: [false, true])
    func everyLevelStaysInsideTheGlass(zUp: Bool) throws {
        let up: SIMD3<Float> = zUp ? SIMD3(0, 0, 1) : SIMD3(0, 1, 0)
        let volume = try #require(LiquidVolume(points: Self.fullLiquid(zUp: zUp), up: up))
        #expect(abs(volume.height - (Self.radius + Self.cut)) < 1e-4)
        let levels: [Float] = [0.02, 0.1, 1.0 / 3, 0.5, 2.0 / 3, 0.9, 1]
        for level in levels {
            let mesh = volume.mesh(level: level)
            #expect(!mesh.positions.isEmpty)
            let outside: Float = mesh.positions.map { simd_length($0) }.max() ?? 0
            #expect(outside < Self.radius + 1e-4, "level \(level): \(outside) m from the centre of a \(Self.radius) m flask")
            let surface: Float = mesh.positions.map { simd_dot($0, up) }.max() ?? 0
            let expected: Float = level * volume.height - Self.radius
            #expect(abs(surface - expected) < 1e-4, "level \(level): surface at \(surface), expected \(expected)")
        }
    }

    @Test func fullItIsTheDesignersLiquid() throws {
        let volume = try #require(LiquidVolume(points: Self.fullLiquid(), up: SIMD3(0, 1, 0)))
        let rim = (Self.radius * Self.radius - Self.cut * Self.cut).squareRoot()
        #expect(abs(volume.radius(at: volume.height) - rim) < 1e-3)
        #expect(simd_distance(volume.widestPoint, .zero) < 0.01)
    }

    @Test func everyFaceTurnsOutwards() throws {
        let volume = try #require(LiquidVolume(points: Self.fullLiquid(), up: SIMD3(0, 1, 0)))
        let mesh = volume.mesh(level: 0.5)
        for first in stride(from: 0, to: mesh.indices.count, by: 3) {
            let corners = (0..<3).map { Int(mesh.indices[first + $0]) }
            let face = simd_cross(mesh.positions[corners[1]] - mesh.positions[corners[0]],
                                  mesh.positions[corners[2]] - mesh.positions[corners[0]])
            guard simd_length(face) > 1e-10 else { continue }
            #expect(simd_dot(face, mesh.normals[corners[0]]) > 0, "triangle \(first / 3)")
        }
    }
}
