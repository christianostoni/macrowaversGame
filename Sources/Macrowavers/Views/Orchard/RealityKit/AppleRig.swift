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
    var profileCount: UInt32
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

/// The spiral-cut apple drawn in RealityKit. Closed, it is the design team's apple (`Apple.usdz`: skin, flesh, stem,
/// leaf); opened, the spiral that the Metal shader deforms (`AppleShape`, the same silhouette) takes its place, in
/// the asset's materials, while the stem and the leaf rise with the top slice. Then the worms. It draws and reports
/// nothing: the opening and the worms come from `OrchardViewModel`. Origin at the centre of the apple.
/// Without the asset the spiral is drawn closed too, in plain materials, with a stick for a stem.
@MainActor
final class AppleRig {
    static let assetName = "Apple"

    let root = Entity()
    let stem = Entity()
    /// Where the orb sits while the apple guards it (centre of the core).
    let core = Entity()
    let shape: AppleShape

    private let body = Entity()
    /// The deformed spiral, shown once the apple opens.
    private let spiral: ModelEntity
    /// The design team's apple without its stem and leaf, shown while it is closed (nil without the asset).
    private let closedApple: Entity?
    private let lowMesh: LowLevelMesh
    private let params: [AppleVertexParams]
    private let paramsBuffer: MTLBuffer?
    private let profileBuffer: MTLBuffer?
    private var worms: [Entity] = []
    /// The worms are the design team's `Worm.usdz`, whose material wriggles them; the stand-in spheres are wriggled
    /// here.
    private var wormsWriggleThemselves = false
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

    init?(shape: AppleShape, wormCount: Int) async {
        self.shape = shape
        let params = Self.makeParams(shape: shape)
        self.params = params
        paramsBuffer = AppleSpiralPipeline.shared.flatMap { Self.makeBuffer(params, device: $0.device) }
        profileBuffer = AppleSpiralPipeline.shared.flatMap { Self.makeBuffer(shape.profile, device: $0.device) }
        guard shape.profile.count > 1, let mesh = try? Self.makeMesh(shape: shape, params: params),
              let resource = try? await MeshResource(from: mesh) else { return nil }
        lowMesh = mesh

        let asset = await Self.loadAsset(height: shape.height)
        closedApple = asset?.apple
        spiral = ModelEntity(mesh: resource, materials: [asset?.flesh ?? Self.fleshMaterial(),
                                                         asset?.skin ?? Self.skinMaterial()])
        body.addChild(spiral)
        if let closedApple = asset?.apple { body.addChild(closedApple) }
        body.position.y = -shape.height / 2
        root.addChild(body)

        core.position = SIMD3(0, shape.height / 2, 0)
        body.addChild(core)
        buildStem(asset?.stemAndLeaf ?? [])
        buildWorms(count: wormCount, template: await Self.loadWorm())
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

    /// Deforms the mesh (only when the opening changes) and moves the stem with the top slice. Closed, the design
    /// team's apple stands in for the spiral.
    func apply(opening: Float) {
        guard opening != appliedOpening else { return }
        appliedOpening = opening
        if let closedApple {
            closedApple.isEnabled = opening <= 0
            spiral.isEnabled = opening > 0
        }
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
            let isVisible = state.visibility > 0.01
            if worm.isEnabled != isVisible { worm.isEnabled = isVisible }
            guard isVisible else { continue }
            worm.position = swarm.position(of: index, opening: opening) - SIMD3(0, 0.012 * (1 - state.visibility), 0)
            worm.orientation = simd_quatf(angle: swarm.heading(of: index), axis: SIMD3(0, 1, 0))
            worm.scale = SIMD3(repeating: max(state.visibility, 0.01))
            worm.setInputTargetEnabled(swarm.isCatchable(index))
            // Wriggle: the segments sway as it crawls.
            for (segment, part) in worm.children.enumerated() where !wormsWriggleThemselves {
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
        guard let profileBuffer, let commandBuffer = pipeline.queue.makeCommandBuffer() else { return }
        // RealityKit hands over the vertex buffer that the GPU will write.
        let vertexBuffer = lowMesh.replace(bufferIndex: 0, using: commandBuffer)
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        var uniforms = AppleUniforms(opening: opening, height: shape.height, maxRadius: shape.maxRadius,
                                     turns: shape.turns, gapPerTurn: shape.gapPerTurn, vertexCount: UInt32(params.count),
                                     profileCount: UInt32(shape.profile.count))
        encoder.setComputePipelineState(pipeline.pipeline)
        encoder.setBuffer(paramsBuffer, offset: 0, index: 0)
        encoder.setBuffer(vertexBuffer, offset: 0, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<AppleUniforms>.stride, index: 2)
        encoder.setBuffer(profileBuffer, offset: 0, index: 3)
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

    private static func makeBuffer<Element>(_ elements: [Element], device: MTLDevice) -> MTLBuffer? {
        elements.withUnsafeBytes { bytes in
            guard let address = bytes.baseAddress else { return nil }
            return device.makeBuffer(bytes: address, length: bytes.count, options: .storageModeShared)
        }
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

    /// The asset's stem and leaf, or a stick without the asset.
    private func buildStem(_ parts: [Entity]) {
        if parts.isEmpty {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: UIColor(red: 0.35, green: 0.22, blue: 0.12, alpha: 1))
            let stick = ModelEntity(mesh: .generateCylinder(height: 0.05, radius: 0.006), materials: [material])
            stick.position = SIMD3(0, 0.025, 0)
            stem.addChild(stick)
        }
        for part in parts {
            stem.addChild(part)
        }
        stem.components.set(AppleStemComponent())
        stem.components.set(CollisionComponent(shapes: [
            // Generous: the stem is thin and the player pinches it while it moves up.
            ShapeResource.generateSphere(radius: 0.06).offsetBy(translation: SIMD3(0, 0.03, 0)),
        ]))
        stem.components.set(InputTargetComponent.disabled)
        stem.components.set(HoverEffectComponent())
        body.addChild(stem)
    }

    /// The worms crawl along +x (their heading turns it), their centre 7 mm above the slice (`WormSwarm.position`).
    /// Each is a copy of `template` (the design team's worm) or, without it, three green spheres.
    private func buildWorms(count: Int, template: Entity?) {
        wormsWriggleThemselves = template != nil
        for index in 0..<count {
            let worm = Entity()
            if let template {
                worm.addChild(template.clone(recursive: true))
            } else {
                for segment in 0..<3 {
                    let part = ModelEntity(mesh: .generateSphere(radius: 0.007), materials: [Self.wormMaterial])
                    part.position = SIMD3(Float(segment - 1) * 0.009, 0, 0)
                    worm.addChild(part)
                }
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

// MARK: - The design team's apple

extension AppleRig {
    private struct Asset {
        /// Skin and flesh, the bottom of the skin on the origin and the apple's axis on the y axis.
        let apple: Entity
        /// Its stem and leaf, placed from the top of the skin (the `stem` entity's origin).
        let stemAndLeaf: [Entity]
        let skin: ShaderGraphMaterial
        let flesh: ShaderGraphMaterial
    }

    /// `Apple.usdz` sized to `height` (the skin's height, as measured for `AppleShape`), split for the rig; nil
    /// without the file or without its `Skin` and `Flesh`.
    private static func loadAsset(height: Float) async -> Asset? {
        guard let asset = try? await Entity(named: assetName, in: .main),
              let skin = asset.findEntity(named: "Skin"), let flesh = asset.findEntity(named: "Flesh"),
              let skinMaterial = material(of: skin), let fleshMaterial = material(of: flesh) else {
            print("⚠️ \(assetName).usdz not found (or without Skin/Flesh): the spiral apple is drawn closed too")
            return nil
        }
        let bounds = skin.visualBounds(relativeTo: asset)
        guard bounds.extents.y > 0 else { return nil }
        asset.scale = SIMD3(repeating: height / bounds.extents.y)
        asset.position = SIMD3(-bounds.center.x, -bounds.min.y, -bounds.center.z) * asset.scale
        let apple = Entity()
        apple.name = assetName
        apple.addChild(asset)
        // The stem and the leaf leave the apple for the `stem` entity, at the top of the skin.
        let top = Entity()
        top.position = SIMD3(0, height, 0)
        apple.addChild(top)
        let stemAndLeaf = ["Stem", "Leaf"].compactMap { asset.findEntity(named: $0) }
        for part in stemAndLeaf {
            let placement = part.transformMatrix(relativeTo: top)
            part.removeFromParent()
            part.transform = Transform(matrix: placement)
        }
        top.removeFromParent()
        return Asset(apple: apple, stemAndLeaf: stemAndLeaf, skin: skinMaterial, flesh: fleshMaterial)
    }

    /// `Worm.usdz` (head along +x), its belly on the slice: the worm's centre is 7 mm above it. Nil without the file.
    private static func loadWorm() async -> Entity? {
        guard let worm = try? await Entity(named: "Worm", in: .main) else {
            print("⚠️ Worm.usdz not found: the worms are green spheres")
            return nil
        }
        let bounds = worm.visualBounds(relativeTo: worm)
        worm.position = SIMD3(-bounds.center.x, -bounds.min.y - 0.007, -bounds.center.z)
        let template = Entity()
        template.name = "Worm"
        template.addChild(worm)
        return template
    }

    /// The airbrush material of an asset part, drawn from both sides (the spiral's faces turn every way).
    private static func material(of part: Entity) -> ShaderGraphMaterial? {
        let model = ([part] + part.allDescendants).lazy.compactMap { $0.components[ModelComponent.self] }.first
        guard var material = model?.materials.first as? ShaderGraphMaterial else { return nil }
        material.faceCulling = .none
        return material
    }
}
