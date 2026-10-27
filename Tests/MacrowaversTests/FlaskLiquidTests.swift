import RealityKit
import simd
import Testing
@testable import Macrowavers

/// The designers' flask: its liquid, built for each level, takes the shape of the glass (it was squashed before,
/// and at a third full stuck out of the round bottom as a disc as wide as the full flask).
@MainActor
struct FlaskLiquidTests {
    @Test func theLiquidTakesTheShapeOfTheGlass() async throws {
        let rig = await ElixirRig.make()
        // As the flask finds it: the first model under the part named "Liquid".
        func firstModel(in entity: Entity) -> ModelEntity? {
            (entity as? ModelEntity) ?? entity.children.lazy.compactMap(firstModel(in:)).first
        }
        let model = try #require(rig.elixir.findEntity(named: "Liquid").flatMap(firstModel(in:)))
        let full = model.visualBounds(relativeTo: rig.elixir)
        let levels = try #require(LiquidLevels(model: model, up: model.convert(direction: SIMD3(0, 1, 0), from: rig.elixir)))
        let volume = levels.volume

        func inFlask(_ point: SIMD3<Float>) -> SIMD3<Float> { rig.elixir.convert(position: point, from: model) }
        let bottom = inFlask(volume.base)
        let height = simd_distance(bottom, inFlask(volume.base + volume.up * volume.height))
        #expect(abs(height - full.extents.y) < 0.005, "height \(height), the liquid's \(full.extents.y)")

        func widest(level: Float) -> Float {
            volume.mesh(level: level).positions.map { point in
                let placed = inFlask(point)
                return simd_distance(SIMD2(placed.x, placed.z), SIMD2(bottom.x, bottom.z))
            }.max() ?? 0
        }
        let fullWidth = max(full.extents.x, full.extents.z) / 2
        #expect(abs(widest(level: 1) - fullWidth) < 0.005, "full: \(widest(level: 1)), the liquid's \(fullWidth)")
        #expect(widest(level: 1.0 / 3) < fullWidth * 0.9, "a third full: \(widest(level: 1.0 / 3)) of \(fullWidth)")
    }
}
