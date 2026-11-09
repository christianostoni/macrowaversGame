import CoreGraphics
import RealityKit
import simd
import Testing
@testable import Macrowavers

/// The designers' flask: its liquid, built for each level, takes the shape of the glass (it was squashed before,
/// and at a third full stuck out of the round bottom as a disc as wide as the full flask). In the game it is the whole
/// liquid in its level material instead; the meshes built for each level are what it falls back to.
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

    /// In the game the liquid is the designers' whole liquid in its level material (`ElixirLiquid.usdz`), cut by a
    /// level surface, not a mesh built for each level.
    @Test func theLiquidWearsItsLevelMaterial() async throws {
        let rig = await ElixirRig.make()
        func firstModel(in entity: Entity) -> ModelEntity? {
            (entity as? ModelEntity) ?? entity.children.lazy.compactMap(firstModel(in:)).first
        }
        let model = try #require(rig.elixir.findEntity(named: "Liquid").flatMap(firstModel(in:)))
        #expect(model.model?.materials.first is ShaderGraphMaterial)
    }

    /// Every input the app sets every frame is in the material: a missing one would leave the liquid uncut.
    @Test func theLevelMaterialTakesEveryInput() async throws {
        var material = try await ShaderGraphMaterial(named: ElixirRig.liquidMaterialPath,
                                                     from: ElixirRig.liquidAssetName, in: .main)
        try material.setParameter(name: "LevelNormal", value: .simd3Float(SIMD3(0, 1, 0)))
        try material.setParameter(name: "LevelOffset", value: .float(0))
        try material.setParameter(name: "Glow", value: .float(1))
        try material.setParameter(name: "Opacity", value: .float(0.9))
        try material.setParameter(name: "Edge", value: .float(0.0015))
        try material.setParameter(name: "Color", value: .color(CGColor(red: 1, green: 0, blue: 0, alpha: 1)))
    }

    /// The surface rises by volume in the round body: empty at the bottom, full at the top, half a sphere at its
    /// middle, slower where it is wide.
    @Test func theSurfaceRisesByVolume() {
        let radius: Float = 0.1
        #expect(ElixirRig.surfaceHeight(fill: 0, radius: radius, full: 0.2) < 1e-4)
        #expect(abs(ElixirRig.surfaceHeight(fill: 1, radius: radius, full: 0.15) - 0.15) < 1e-4)
        #expect(abs(ElixirRig.surfaceHeight(fill: 0.5, radius: radius, full: 0.2) - radius) < 1e-4)
        let heights = stride(from: Float(0), through: 1, by: 0.1).map {
            ElixirRig.surfaceHeight(fill: $0, radius: radius, full: 0.2)
        }
        #expect(zip(heights, heights.dropFirst()).allSatisfy { $0 < $1 })
        // Around the middle a tenth of the flask raises it less than at the bottom.
        #expect(heights[6] - heights[5] < heights[1] - heights[0])
    }
}
