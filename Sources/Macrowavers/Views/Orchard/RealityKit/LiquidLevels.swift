import RealityKit
import simd

/// Shows the flask's liquid at its level (`LiquidVolume`): one mesh per step of level, all built once in the
/// background when the flask loads (`prepare()`), and swapped into the liquid's model, which keeps its material.
/// Built while the liquid rose, they held up frames.
@MainActor
final class LiquidLevels {
    /// Steps of level: under 2 mm each in the flask.
    static let steps = 48

    let volume: LiquidVolume
    private let model: ModelEntity
    private var meshes: [Int: MeshResource] = [:]
    private var shown: Int?

    /// nil when the model has no mesh to take the inside of the glass from.
    /// - Parameter up: which way is up in the model's space.
    init?(model: ModelEntity, up: SIMD3<Float>) {
        guard let mesh = model.model?.mesh,
              let volume = LiquidVolume(points: Self.points(of: mesh), up: up) else { return nil }
        self.model = model
        self.volume = volume
    }

    /// Builds every step's mesh (light ones: ~1k vertices each), without holding up a frame.
    func prepare() async {
        for step in 1...Self.steps where meshes[step] == nil {
            meshes[step] = try? await MeshResource(from: [Self.descriptor(volume.mesh(level: Float(step) / Float(Self.steps)))])
        }
    }

    /// The liquid filled to `fill` (0…1).
    func show(_ fill: Float) {
        let step = max(1, Int((min(max(fill, 0), 1) * Float(Self.steps)).rounded()))
        guard step != shown else { return }
        if meshes[step] == nil {
            // Not prepared yet (the flask has just loaded): built now.
            meshes[step] = try? MeshResource.generate(from: [Self.descriptor(volume.mesh(level: Float(step) / Float(Self.steps)))])
        }
        guard let mesh = meshes[step] else { return }
        model.model?.mesh = mesh
        shown = step
    }

    private static func descriptor(_ mesh: LiquidVolume.Mesh) -> MeshDescriptor {
        var descriptor = MeshDescriptor(name: "Liquid")
        descriptor.positions = MeshBuffers.Positions(mesh.positions)
        descriptor.normals = MeshBuffers.Normals(mesh.normals)
        descriptor.primitives = .triangles(mesh.indices)
        return descriptor
    }

    /// Every vertex of the mesh, in its model's space.
    private static func points(of mesh: MeshResource) -> [SIMD3<Float>] {
        let contents = mesh.contents
        return contents.instances.flatMap { instance -> [SIMD3<Float>] in
            guard let model = contents.models[instance.model] else { return [] }
            return model.parts.flatMap { part in
                part.positions.elements.map { point in
                    let placed = instance.transform * SIMD4(point, 1)
                    return SIMD3(placed.x, placed.y, placed.z)
                }
            }
        }
    }
}
