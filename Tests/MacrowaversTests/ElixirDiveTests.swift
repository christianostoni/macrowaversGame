import RealityKit
import simd
import Testing
@testable import Macrowavers

/// An ingredient diving into the flask: until it drops into the neck it stays out of the glass, and its glow (a quad
/// drawn without depth) and its sparks are gone before it gets there, or they show through the glass. Uses the real
/// flask, standing at the orbit's centre at its scale in the game.
@MainActor
struct ElixirDiveTests {
    private struct Flask {
        let neckTop: SIMD3<Float>
        let neckBase: SIMD3<Float>
        /// The round body (glass and liquid, not the particles: their bounds are infinite) as an upright cylinder up
        /// to the neck's base, and the neck as a tube as wide as the cork along its own (leaning) axis.
        let axis: SIMD2<Float>
        let radius: Float
        let bottom: Float
        let neckRadius: Float

        /// The point is within `margin` of the flask.
        func contains(_ point: SIMD3<Float>, margin: Float) -> Bool {
            let inBody = simd_distance(SIMD2(point.x, point.z), axis) < radius + margin
                && point.y > bottom - margin && point.y < neckBase.y + margin
            let along = simd_clamp(simd_dot(point - neckBase, neckTop - neckBase) / simd_length_squared(neckTop - neckBase),
                                   0, 1)
            let inNeck = simd_distance(point, neckBase + (neckTop - neckBase) * along) < neckRadius + margin
            return inBody || inNeck
        }
    }

    private func flask(on orbit: ElixirOrbit) async -> Flask {
        let rig = await ElixirRig.make()
        let scale = ElixirRig.flaskScale
        let neck = rig.neck(relativeTo: rig.elixir)
        var bounds = BoundingBox.empty
        var cork = BoundingBox.empty
        var pending: [Entity] = [rig.elixir]
        while let entity = pending.popLast() {
            pending.append(contentsOf: entity.children)
            guard entity.components.has(ModelComponent.self) else { continue }
            let box = entity.visualBounds(recursive: false, relativeTo: rig.elixir)
            if entity.name == "Cork" { cork = box } else { bounds = bounds.union(box) }
        }
        let middle = (bounds.min + bounds.max) / 2 * scale
        return Flask(neckTop: orbit.center + neck.top * scale, neckBase: orbit.center + neck.base * scale,
                     axis: SIMD2(orbit.center.x + middle.x, orbit.center.z + middle.z),
                     radius: max(bounds.extents.x, bounds.extents.z) / 2 * scale,
                     bottom: orbit.center.y + bounds.min.y * scale,
                     neckRadius: max(cork.extents.x, cork.extents.z) / 2 * scale)
    }

    /// Until it drops into the neck, the gem (6 cm tall at full size) stays out of the flask.
    @Test func gemStaysClearOfTheFlaskUntilItDrops() async {
        let orbit = ElixirOrbit()
        let flask = await flask(on: orbit)
        for slot in 0..<Elixir.ingredientCount {
            for step in 0...60 {
                let progress = ElixirOrbit.diveArc * Float(step) / 60
                let gem = orbit.divePosition(slot: slot, progress: progress, neckTop: flask.neckTop,
                                             neckBase: flask.neckBase)
                #expect(!flask.contains(gem, margin: 0.03), "slot \(slot) at \(progress): \(gem) in the flask")
            }
        }
    }

    @Test func glowNeverReachesTheNeck() async {
        let orbit = ElixirOrbit()
        let flask = await flask(on: orbit)
        let fade = OrchardSystem.diveGlowFade
        for slot in 0..<Elixir.ingredientCount {
            for step in 0...100 {
                let progress = Float(step) / 100
                let gem = orbit.divePosition(slot: slot, progress: progress, neckTop: flask.neckTop,
                                             neckBase: flask.neckBase)
                let glowRadius = OrchardSceneBuilder.glowSize / 2
                    * (1 - Elixir.smoothstep(from: fade.lowerBound, to: fade.upperBound, progress))
                let distance = simd_distance(gem, flask.neckTop)
                #expect(glowRadius < 0.001 || distance > glowRadius,
                        "slot \(slot) at \(progress): glow \(glowRadius) m, \(distance) m from the neck")
            }
        }
    }

    @Test func sparksStopAboveTheNeck() async {
        let orbit = ElixirOrbit()
        let flask = await flask(on: orbit)
        for slot in 0..<Elixir.ingredientCount {
            let gem = orbit.divePosition(slot: slot, progress: OrchardSystem.diveSparksStop,
                                         neckTop: flask.neckTop, neckBase: flask.neckBase)
            #expect(gem.y > flask.neckTop.y + 0.05, "slot \(slot): \(gem.y - flask.neckTop.y) m above the neck")
        }
    }
}
