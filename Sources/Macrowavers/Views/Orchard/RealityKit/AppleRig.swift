import Metal
import RealityKit
import simd
import UIKit

// MARK: - Types shared with the shader (layout must match AppleSpiral.metal)

/// Fixed parameters of one vertex, generated once on the CPU.
struct AppleVertexParams {
    var theta: Float
    var radial: Float
    var vertical: Float
    /// `AppleShape.Surface` raw value.
    var surface: UInt32
}

/// Vertex written by the shader (`float3` is 16 bytes in Metal, like `SIMD3<Float>`).
struct AppleVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
}

struct AppleUniforms {
    var opening: Float
    var height: Float
    var maxRadius: Float
    var turns: Float
    var gapPerTurn: Float
    var vertexCount: UInt32
}

/// Compute pipeline of the `deformApple` kernel, created once and shared by every apple.
/// `nil` if Metal is not available: the apples are then deformed on the CPU (same maths, `AppleShape`).
@MainActor
final class AppleSpiralPipeline {
    static let shared = AppleSpiralPipeline()

    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLComputePipelineState

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let function = device.makeDefaultLibrary()?.makeFunction(name: "deformApple"),
              let pipeline = try? device.makeComputePipelineState(function: function) else {
            print("⚠️ Metal apple shader unavailable: apples are deformed on the CPU")
            return nil
        }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
    }
}

/// The spiral-cut apple drawn in RealityKit: the mesh deformed by the Metal shader, the stem to pull and
/// the worms. It draws and reports nothing: the opening and the worms come from `OrchardViewModel`.
/// Origin at the centre of the apple.
@MainActor
final class AppleRig {
    let root = Entity()
    let stem = Entity()
    /// Where the orb sits while the apple guards it (centre of the core).
    let core = Entity()
    let shape: AppleShape

    private let body = Entity()
    private let lowMesh: LowLevelMesh
    private let params: [AppleVertexParams]
    private let paramsBuffer: MTLBuffer?
    private var worms: [Entity] = []
    private var appliedOpening: Float = -1
    /// Opening currently drawn: it eases towards the requested one, so the apple never snaps shut.
    private(set) var displayedOpening: Float = 0
    /// Worms already caught (to play the catch animation once).
    private var caughtShown: Set<Int> = []

    private static let wormMaterial: PhysicallyBasedMaterial = {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.45, green: 0.8, blue: 0.3, alpha: 1))
        material.roughness = 0.6
        return material
    }()

    init?(shape: AppleShape, wormCount: Int) {
        self.shape = shape
        let params = Self.makeParams(shape: shape)
        self.params = params
        paramsBuffer = AppleSpiralPipeline.shared.flatMap { pipeline in
            params.withUnsafeBytes { bytes in
                guard let address = bytes.baseAddress else { return nil }
                return pipeline.device.makeBuffer(bytes: address, length: bytes.count, options: .storageModeShared)
            }
        }
        guard let mesh = try? Self.makeMesh(shape: shape, params: params),
              let resource = try? MeshResource(from: mesh) else { return nil }
        lowMesh = mesh

        let apple = ModelEntity(mesh: resource, materials: [Self.fleshMaterial(), Self.skinMaterial()])
        body.addChild(apple)
        body.position.y = -shape.height / 2
        root.addChild(body)

        core.position = SIMD3(0, shape.height / 2, 0)
        body.addChild(core)
        buildStem()
        buildWorms(count: wormCount)
        apply(opening: 0)
    }

    // MARK: - Updates from the view model

    /// Moves the drawn opening towards `target` (quick while pulling, gentle when the apple closes again).
    func ease(towards target: Float, deltaTime: Float) {
        let rate: Float = target < displayedOpening ? 4 : 14
        displayedOpening += (target - displayedOpening) * (1 - exp(-deltaTime * rate))
        if abs(target - displayedOpening) < 0.002 { displayedOpening = target }
        apply(opening: displayedOpening)
    }

    /// Deforms the mesh (only when the opening changes) and moves the stem with the top slice.
    func apply(opening: Float) {
        guard opening != appliedOpening else { return }
        appliedOpening = opening
        if let pipeline = AppleSpiralPipeline.shared, let paramsBuffer {
            deformOnGPU(opening: opening, pipeline: pipeline, paramsBuffer: paramsBuffer)
        } else {
            deformOnCPU(opening: opening)
        }
        stem.position = SIMD3(0, shape.height + opening * shape.maxLift, 0)
    }

    /// Places the worms on their slices; caught worms jump out and vanish.
    func apply(worms swarm: WormSwarm, opening: Float, time: Float) {
        for (index, worm) in worms.enumerated() where index < swarm.worms.count {
            let state = swarm.worms[index]
            if state.isCaught {
                guard !caughtShown.contains(index) else { continue }
                caughtShown.insert(index)
                var jump = worm.transform
                jump.translation += SIMD3(0, 0.06, 0)
                jump.scale = .zero
                worm.move(to: jump, relativeTo: worm.parent, duration: 0.35)
                worm.components[InputTargetComponent.self]?.isEnabled = false
                continue
            }
            caughtShown.remove(index)
            worm.isEnabled = state.visibility > 0.01
            worm.position = swarm.position(of: index, opening: opening) - SIMD3(0, 0.012 * (1 - state.visibility), 0)
            worm.orientation = simd_quatf(angle: swarm.heading(of: index), axis: SIMD3(0, 1, 0))
            worm.scale = SIMD3(repeating: max(state.visibility, 0.01))
            worm.components[InputTargetComponent.self]?.isEnabled = swarm.isCatchable(index)
            // Wriggle: the segments sway as it crawls.
            for (segment, part) in worm.children.enumerated() {
                part.position.z = 0.002 * sin(time * 12 + Float(segment) * 1.8)
            }
        }
    }

    /// The stem and the worms answer to gestures only while the apple is close to the player.
    func setInteractive(_ isInteractive: Bool) {
        stem.components[InputTargetComponent.self]?.isEnabled = isInteractive
        if !isInteractive {
            for worm in worms {
                worm.isEnabled = false
                worm.components[InputTargetComponent.self]?.isEnabled = false
            }
        }
    }

    /// Worms back inside, apple closed (after a restart or when it goes back to the tree).
    func resetWorms() {
        caughtShown = []
        for worm in worms {
            worm.isEnabled = false
            worm.scale = SIMD3(repeating: 0.01)
        }
    }

    // MARK: - Deformation

    private func deformOnGPU(opening: Float, pipeline: AppleSpiralPipeline, paramsBuffer: MTLBuffer) {
        guard let commandBuffer = pipeline.queue.makeCommandBuffer() else { return }
        // RealityKit hands over the vertex buffer that the GPU will write.
        let vertexBuffer = lowMesh.replace(bufferIndex: 0, using: commandBuffer)
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        var uniforms = AppleUniforms(opening: opening, height: shape.height, maxRadius: shape.maxRadius,
                                     turns: shape.turns, gapPerTurn: shape.gapPerTurn, vertexCount: UInt32(params.count))
        encoder.setComputePipelineState(pipeline.pipeline)
        encoder.setBuffer(paramsBuffer, offset: 0, index: 0)
        encoder.setBuffer(vertexBuffer, offset: 0, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<AppleUniforms>.stride, index: 2)
        encoder.dispatchThreads(MTLSize(width: params.count, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: min(64, pipeline.pipeline.maxTotalThreadsPerThreadgroup),
                                                               height: 1, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
    }

    /// Same result as the shader, computed on the CPU (no Metal, e.g. some test environments).
    private func deformOnCPU(opening: Float) {
        let shape = shape
        let params = params
        lowMesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let vertices = raw.bindMemory(to: AppleVertex.self)
            for (index, param) in params.enumerated() where index < vertices.count {
                let surface = AppleShape.Surface(rawValue: param.surface) ?? .skin
                vertices[index] = AppleVertex(
                    position: shape.point(theta: param.theta, radial: param.radial, vertical: param.vertical,
                                          surface: surface, opening: opening),
                    normal: shape.normal(theta: param.theta, radial: param.radial, vertical: param.vertical,
                                         surface: surface, opening: opening))
            }
        }
    }

    // MARK: - Geometry

    /// Parameters of every vertex: flesh top and bottom faces (radial grid) and skin (vertical grid).
    private static func makeParams(shape: AppleShape) -> [AppleVertexParams] {
        var params: [AppleVertexParams] = []
        for surface in [AppleShape.Surface.top, .bottom] {
            for thetaIndex in 0..<thetaSamples(shape) {
                for radialIndex in 0..<radialSamples {
                    params.append(AppleVertexParams(theta: theta(thetaIndex, shape: shape),
                                                    radial: Float(radialIndex) / Float(radialSamples - 1),
                                                    vertical: 0, surface: surface.rawValue))
                }
            }
        }
        for thetaIndex in 0..<thetaSamples(shape) {
            for verticalIndex in 0..<verticalSamples {
                params.append(AppleVertexParams(theta: theta(thetaIndex, shape: shape), radial: 1,
                                                vertical: Float(verticalIndex) / Float(verticalSamples - 1),
                                                surface: AppleShape.Surface.skin.rawValue))
            }
        }
        return params
    }

    private static let segmentsPerTurn = 64
    /// Samples from the centre to the edge (flesh faces).
    private static let radialSamples = 10
    /// Samples along the height of the skin.
    private static let verticalSamples = 5

    private static func thetaSamples(_ shape: AppleShape) -> Int {
        Int(shape.turns + 2) * segmentsPerTurn + 1
    }

    private static func theta(_ index: Int, shape: AppleShape) -> Float {
        shape.thetaStart + (shape.thetaEnd - shape.thetaStart) * Float(index) / Float(thetaSamples(shape) - 1)
    }

    private static func makeMesh(shape: AppleShape, params: [AppleVertexParams]) throws -> LowLevelMesh {
        let rows = thetaSamples(shape)
        let fleshFace = rows * radialSamples
        var fleshIndices: [UInt32] = []
        gridIndices(&fleshIndices, base: 0, rows: rows, columns: radialSamples)
        gridIndices(&fleshIndices, base: UInt32(fleshFace), rows: rows, columns: radialSamples)
        var skinIndices: [UInt32] = []
        gridIndices(&skinIndices, base: UInt32(2 * fleshFace), rows: rows, columns: verticalSamples)

        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, offset: MemoryLayout<AppleVertex>.offset(of: \.position) ?? 0),
            .init(semantic: .normal, format: .float3, offset: MemoryLayout<AppleVertex>.offset(of: \.normal) ?? 16),
        ]
        descriptor.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<AppleVertex>.stride)]
        descriptor.vertexCapacity = params.count
        descriptor.indexCapacity = fleshIndices.count + skinIndices.count
        descriptor.indexType = .uint32

        let mesh = try LowLevelMesh(descriptor: descriptor)
        let allIndices = fleshIndices + skinIndices
        mesh.withUnsafeMutableIndices { raw in
            let destination = raw.bindMemory(to: UInt32.self)
            for index in allIndices.indices { destination[index] = allIndices[index] }
        }
        // Generous bounds covering the fully open apple (avoids wrong culling).
        let radius = shape.maxRadius
        let bounds = BoundingBox(min: SIMD3(-radius, 0, -radius),
                                 max: SIMD3(radius, shape.height + shape.maxLift + 0.01, radius))
        mesh.parts.replaceAll([
            LowLevelMesh.Part(indexOffset: 0, indexCount: fleshIndices.count, topology: .triangle,
                              materialIndex: 0, bounds: bounds),
            LowLevelMesh.Part(indexOffset: fleshIndices.count * MemoryLayout<UInt32>.stride, // bytes
                              indexCount: skinIndices.count, topology: .triangle, materialIndex: 1, bounds: bounds),
        ])
        return mesh
    }

    private static func gridIndices(_ indices: inout [UInt32], base: UInt32, rows: Int, columns: Int) {
        for row in 0..<(rows - 1) {
            for column in 0..<(columns - 1) {
                let first = base + UInt32(row * columns + column)
                let below = first + UInt32(columns)
                indices += [first, below, first + 1, first + 1, below, below + 1]
            }
        }
    }

    // MARK: - Stem and worms

    private func buildStem() {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.35, green: 0.22, blue: 0.12, alpha: 1))
        let stick = ModelEntity(mesh: .generateCylinder(height: 0.05, radius: 0.006), materials: [material])
        stick.position = SIMD3(0, 0.025, 0)
        stem.addChild(stick)
        stem.components.set(AppleStemComponent())
        stem.components.set(CollisionComponent(shapes: [
            // Generous: the stem is thin and the player pinches it while it moves up.
            ShapeResource.generateSphere(radius: 0.06).offsetBy(translation: SIMD3(0, 0.03, 0)),
        ]))
        stem.components.set(InputTargetComponent.disabled)
        stem.components.set(HoverEffectComponent())
        body.addChild(stem)
    }

    private func buildWorms(count: Int) {
        for index in 0..<count {
            let worm = Entity()
            for segment in 0..<3 {
                let part = ModelEntity(mesh: .generateSphere(radius: 0.007), materials: [Self.wormMaterial])
                part.position = SIMD3(Float(segment - 1) * 0.009, 0, 0)
                worm.addChild(part)
            }
            worm.components.set(WormComponent(index: index))
            // Larger than the worm: easier to look at and tap while it crawls.
            worm.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.035)]))
            worm.components.set(InputTargetComponent.disabled)
            worm.components.set(HoverEffectComponent())
            worm.isEnabled = false
            body.addChild(worm)
            worms.append(worm)
        }
    }

    // MARK: - Materials

    private static func fleshMaterial() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.98, green: 0.95, blue: 0.84, alpha: 1))
        material.roughness = 0.8
        material.faceCulling = .none
        return material
    }

    private static func skinMaterial() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.78, green: 0.12, blue: 0.15, alpha: 1))
        material.roughness = 0.35
        material.faceCulling = .none
        return material
    }
}
