import Foundation
import Metal
import RealityKit
import simd
import UIKit

/// The scroll's collider: pinch it to open it, drag it to read (`DragonImmersiveView`).
struct ScrollHandleComponent: Component {}

/// The story's scroll in the room (`StoryScroll` is how the player handles it): its paper, rolled to the scroll's
/// pose every time it changes, its rods, and where it floats: in front of the player, a little below their eyes,
/// gliding back in front of them if they turn away or stand up (never while they hold it).
struct ScrollComponent: Component {
    let scroll: StoryScroll
    let viewer: ViewerTracker
    let paper: ScrollPaper
    /// The words under the scroll (an attachment, outside the scroll: it is never disabled, it hides itself).
    let hint: Entity?
    /// The pose the paper has been rolled to.
    var shownPose: ScrollRoll.Pose?
    /// Where the window's top edge rests (scene) and which way the scroll faces (yaw).
    var spot: SIMD3<Float>?
    var yaw: Float = 0
    /// Placed where the tracked eyes were (not the seated fallback's), and how long it has waited for them (s).
    var isPlacedFromTrackedEyes = false
    var waitedForEyes: Float = 0

    /// The scroll this far in front of the eyes (m).
    static let distance: Float = 0.95
    /// Its window's top edge this far above the eyes: the open page sits a little below them (m).
    static let rise: Float = 0.15
    /// Looking further away than this brings it back in front of the eyes; so do moving this far (m) or standing up.
    static let lookAwayAngle: Float = 40 * .pi / 180
    static let driftTolerance: Float = 0.3
    /// How fast it glides to its spot (1/s).
    static let responsiveness: Float = 3
    /// It appears once the eyes are tracked (when the space opens, head tracking takes a moment to start), or
    /// after this long without them (s): in front of a seated player at the space's origin.
    static let eyesWait: Float = 3
    /// The words this far under the bottom roll (m).
    static let hintDrop: Float = 0.09
}

/// The paper's mesh, rewritten in place for each pose (~700 vertices), and the rods it rolls around.
@MainActor
final class ScrollPaper {
    let roll: ScrollRoll
    let rows: [Float]
    let entity: ModelEntity
    let handle: Entity
    private let mesh: LowLevelMesh
    private let parts: [ScrollRoll.MeshPart: Range<Int>]
    private let topRod: Entity
    private let bottomRod: Entity

    /// One vertex in the mesh's buffer, packed (32 bytes): position, normal, texture coordinates.
    private struct Vertex {
        var px: Float = 0, py: Float = 0, pz: Float = 0
        var nx: Float = 0, ny: Float = 0, nz: Float = 0
        var tu: Float = 0, tv: Float = 0
    }

    /// The materials, in the order of `materialIndex`.
    private enum Material: Int {
        case page, silk, back
    }

    init?(roll: ScrollRoll, page: TextureResource, looks: ScrollLooks) {
        let shape = roll.mesh(pose: roll.pose(open: 0, scroll: 0))
        let descriptor = LowLevelMesh.Descriptor(
            vertexCapacity: shape.positions.count,
            vertexAttributes: [
                .init(semantic: .position, format: .float3, offset: 0),
                .init(semantic: .normal, format: .float3, offset: 12),
                .init(semantic: .uv0, format: .float2, offset: 24),
            ],
            vertexLayouts: [.init(bufferIndex: 0, bufferStride: MemoryLayout<Vertex>.stride)],
            indexCapacity: shape.indices.count)
        guard MemoryLayout<Vertex>.stride == 32, let mesh = try? LowLevelMesh(descriptor: descriptor) else { return nil }
        mesh.withUnsafeMutableIndices { buffer in
            let indices = buffer.bindMemory(to: UInt32.self)
            for (index, value) in shape.indices.enumerated() { indices[index] = value }
        }
        Self.write(shape.positions, shape.normals, uvs: shape.uvs, to: mesh)
        guard let resource = try? MeshResource(from: mesh) else { return nil }
        let model = ModelEntity(mesh: resource, materials: Self.materials(page: page, looks: looks))
        model.name = "ScrollPaper"
        let handle = Entity()
        handle.name = "ScrollHandle"
        let rods = (Self.makeRod(width: roll.width, radius: roll.coreRadius, looks: looks),
                    Self.makeRod(width: roll.width, radius: roll.coreRadius, looks: looks))
        for child in [model, rods.0, rods.1] { handle.addChild(child) }
        handle.components.set(ScrollHandleComponent())
        handle.components.set(InputTargetComponent())
        handle.components.set(HoverEffectComponent())
        self.roll = roll
        rows = shape.rows
        parts = shape.parts
        self.mesh = mesh
        entity = model
        self.handle = handle
        (topRod, bottomRod) = rods
        updateParts(positions: shape.positions)
    }

    /// Rolls the paper to `pose`: its vertices, its rods and the collider around it.
    func show(_ pose: ScrollRoll.Pose) {
        let (positions, normals) = roll.vertices(rows: rows, pose: pose)
        Self.write(positions, normals, uvs: nil, to: mesh)
        updateParts(positions: positions)
        let rods = roll.rods(pose)
        topRod.position = SIMD3(0, rods.top.x, rods.top.y)
        bottomRod.position = SIMD3(0, rods.bottom.x, rods.bottom.y)
        // From the top roll's top to the bottom roll's bottom, rods and knobs included.
        let rolled = roll.rolled(pose)
        let top = roll.radius(rolled: rolled.top), bottom = roll.radius(rolled: rolled.bottom)
        let depth = 2 * max(top, bottom)
        let size = SIMD3(roll.width + 0.08, pose.window + top + bottom, depth + 0.02)
        let box = ShapeResource.generateBox(size: size)
            .offsetBy(translation: SIMD3(0, top - size.y / 2, depth / 2 - 0.01))
        handle.components.set(CollisionComponent(shapes: [box]))
    }

    private func updateParts(positions: [SIMD3<Float>]) {
        let bounds = positions.reduce(BoundingBox.empty) { $0.union($1) }
        let material: [ScrollRoll.MeshPart: Material] = [.page: .page, .frontLeads: .silk, .back: .back, .backLeads: .silk]
        mesh.parts.replaceAll(ScrollRoll.MeshPart.allCases.compactMap { part in
            guard let range = parts[part], !range.isEmpty, let index = material[part] else { return nil }
            return LowLevelMesh.Part(indexOffset: range.lowerBound * MemoryLayout<UInt32>.stride, indexCount: range.count,
                                     topology: .triangle, materialIndex: index.rawValue, bounds: bounds)
        })
    }

    private static func write(_ positions: [SIMD3<Float>], _ normals: [SIMD3<Float>], uvs: [SIMD2<Float>]?,
                              to mesh: LowLevelMesh) {
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { buffer in
            let vertices = buffer.bindMemory(to: Vertex.self)
            for index in positions.indices {
                let position = positions[index], normal = normals[index]
                (vertices[index].px, vertices[index].py, vertices[index].pz) = (position.x, position.y, position.z)
                (vertices[index].nx, vertices[index].ny, vertices[index].nz) = (normal.x, normal.y, normal.z)
                if let uv = uvs?[index] { (vertices[index].tu, vertices[index].tv) = (uv.x, uv.y) }
            }
        }
    }

    /// The page, unlit in its painted colours (lit, tone mapping washed them out), like the game's airbrush
    /// materials; the silk at the ends and the back of the paper in the game's airbrush.
    private static func materials(page: TextureResource, looks: ScrollLooks) -> [any RealityKit.Material] {
        var front = UnlitMaterial(applyPostProcessToneMap: false)
        front.color = .init(texture: .init(page))
        return [front, looks.silk, looks.back]
    }

    /// A rod along x, a little wider than the paper: a low-poly prism with a crystal at each end.
    private static func makeRod(width: Float, radius: Float, looks: ScrollLooks) -> Entity {
        let rodLength = width + 0.03
        let assembly = Entity()
        if let prism = Facets.prism(sides: 6, radius: radius * 0.8, length: rodLength) {
            assembly.addChild(ModelEntity(mesh: prism, materials: [looks.rod]))
        }
        for side: Float in [-1, 1] {
            guard let crystal = Facets.crystal(length: radius * 3.2, radius: radius * 1.3) else { continue }
            let knob = ModelEntity(mesh: crystal, materials: [looks.knob])
            knob.position = SIMD3(side * (rodLength / 2 + radius * 1.4), 0, 0)
            assembly.addChild(knob)
        }
        return assembly
    }
}

/// The scroll's materials in the game's style: the design team's airbrush shader graph (taken from the island's
/// file: a colour ramp across each face, from facing the player to its edges, with grain), each with its own colours,
/// as bright as the island's. Without the island's file, plain lit colours.
@MainActor
struct ScrollLooks {
    let silk: any RealityKit.Material
    let back: any RealityKit.Material
    let rod: any RealityKit.Material
    let knob: any RealityKit.Material

    /// The ramps' four colours (linear), from facing the player to the edges.
    private static let silkRamp: [SIMD3<Float>] = [[0.0288, 0.0128, 0.06], [0.216, 0.096, 0.45], [0.36, 0.16, 0.75],
                                                   [0.648, 0.538, 0.8625]]
    private static let paperRamp: [SIMD3<Float>] = [[0.4, 0.29, 0.14], [0.66, 0.5, 0.27], [0.88, 0.76, 0.52],
                                                    [0.98, 0.93, 0.82]]
    /// The paper's rolls a little brighter where they face the player than the island's rock (paper, not stone).
    private static let paperEmissionBoost: Float = -0.3
    /// The grain is noise in the model's own space, this many specks a unit: the island is modelled ~14 m wide and
    /// shrunk to ~2.5 m, the scroll is in metres, so its grain needs ~5.6 times the trunk's (183) to look the same.
    private static let grainScale: Float = 1000
    private static let goldRamp: [SIMD3<Float>] = [[0.076, 0.06, 0.012], [0.57, 0.45, 0.09], [0.95, 0.75, 0.15],
                                                   [0.9725, 0.8625, 0.5325]]

    static func load() async -> ScrollLooks {
        // The tree trunk's material: its ramp is the rods' wood as it is.
        let path = "/root/_materials/Airbrush_Trunk"
        guard var trunk = try? await ShaderGraphMaterial(named: path, from: "\(IslandSceneBuilder.islandName).usdz", in: .main) else {
            print("⚠️ The island's airbrush material was not found: the scroll's rods and rolls are plain")
            return ScrollLooks(silk: plain(silkRamp[2]), back: plain(paperRamp[2]), rod: plain([0.5, 0.3, 0.1]),
                               knob: plain(goldRamp[2]))
        }
        try? trunk.setParameter(name: "EmissionBoost", value: .float(IslandSceneBuilder.islandEmissionBoost))
        try? trunk.setParameter(name: "GrainScale", value: .float(grainScale))
        func recoloured(_ ramp: [SIMD3<Float>], emissionBoost: Float = IslandSceneBuilder.islandEmissionBoost) -> ShaderGraphMaterial {
            var material = trunk
            try? material.setParameter(name: "EmissionBoost", value: .float(emissionBoost))
            for (index, colour) in ramp.enumerated() {
                let components = [CGFloat(colour.x), CGFloat(colour.y), CGFloat(colour.z), 1]
                guard let space = CGColorSpace(name: CGColorSpace.linearSRGB),
                      let color = CGColor(colorSpace: space, components: components) else { continue }
                try? material.setParameter(name: "Stop\(index)Color", value: .color(color))
            }
            return material
        }
        return ScrollLooks(silk: recoloured(silkRamp), back: recoloured(paperRamp, emissionBoost: paperEmissionBoost),
                           rod: trunk, knob: recoloured(goldRamp))
    }

    private static func plain(_ colour: SIMD3<Float>) -> any RealityKit.Material {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: CGFloat(colour.x), green: CGFloat(colour.y),
                                                 blue: CGFloat(colour.z), alpha: 1))
        material.roughness = 0.6
        return material
    }
}

/// Low-poly pieces in the game's faceted style: flat faces, each with its own vertices.
private enum Facets {
    /// A prism along x: `sides` long faces and two ends.
    static func prism(sides: Int, radius: Float, length: Float) -> MeshResource? {
        let ring = (0..<sides).map { side -> SIMD2<Float> in
            let angle = 2 * Float.pi * Float(side) / Float(sides)
            return SIMD2(radius * cos(angle), radius * sin(angle))
        }
        let half = length / 2
        var triangles: [[SIMD3<Float>]] = []
        for side in 0..<sides {
            let this = ring[side], next = ring[(side + 1) % sides]
            let corners = [SIMD3(-half, this.x, this.y), SIMD3(half, this.x, this.y),
                           SIMD3(half, next.x, next.y), SIMD3(-half, next.x, next.y)]
            triangles += [[corners[0], corners[1], corners[2]], [corners[0], corners[2], corners[3]]]
            for end in [-half, half] {
                triangles.append([SIMD3(end, 0, 0), SIMD3(end, this.x, this.y), SIMD3(end, next.x, next.y)])
            }
        }
        return mesh(triangles)
    }

    /// A crystal along x, like the island's floating gems: two pyramids on a square.
    static func crystal(length: Float, radius: Float) -> MeshResource? {
        let tips = [SIMD3<Float>(-length / 2, 0, 0), SIMD3<Float>(length / 2, 0, 0)]
        let square = [SIMD3<Float>(0, radius, 0), SIMD3<Float>(0, 0, radius), SIMD3<Float>(0, -radius, 0),
                      SIMD3<Float>(0, 0, -radius)]
        let triangles = tips.flatMap { tip in
            (0..<4).map { [tip, square[$0], square[($0 + 1) % 4]] }
        }
        return mesh(triangles)
    }

    /// Flat-shaded triangles of a convex shape around the origin, each turned to face outwards.
    private static func mesh(_ triangles: [[SIMD3<Float>]]) -> MeshResource? {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        for triangle in triangles {
            var corners = triangle
            var normal = simd_cross(corners[1] - corners[0], corners[2] - corners[0])
            guard simd_length(normal) > 1e-9 else { continue }
            if simd_dot(normal, corners[0] + corners[1] + corners[2]) < 0 {
                corners.swapAt(1, 2)
                normal = -normal
            }
            positions += corners
            normals += Array(repeating: simd_normalize(normal), count: 3)
        }
        var descriptor = MeshDescriptor(name: "Facets")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles((0..<UInt32(positions.count)).map { $0 })
        return try? MeshResource.generate(from: [descriptor])
    }
}

@MainActor
enum ScrollSceneBuilder {
    /// The scroll's page, made by `Assets/Scroll/make_scroll_page.swift`.
    static let pageName = "ScrollPage"
    /// The paper's width (m): the page's length follows from its image's proportions.
    static let width: Float = 0.45

    /// The scroll, hidden until the story reaches it. Nil without its page: the story can still skip it.
    static func makeScroll(scroll: StoryScroll, viewer: ViewerTracker, hint: Entity?) async -> Entity? {
        guard let url = Bundle.main.url(forResource: pageName, withExtension: "jpg"),
              let page = try? await TextureResource(contentsOf: url, options: .init(semantic: .color)),
              page.width > 0,
              let paper = ScrollPaper(roll: ScrollRoll(width: width, pageLength: width * Float(page.height) / Float(page.width)),
                                      page: page, looks: await ScrollLooks.load()) else {
            print("⚠️ \(pageName).jpg not found: the story's scroll can only be skipped")
            return nil
        }
        scroll.roll = paper.roll
        let root = Entity()
        root.name = "StoryScroll"
        root.addChild(paper.handle)
        root.components.set(OpacityComponent(opacity: 0))
        root.components.set(ScrollComponent(scroll: scroll, viewer: viewer, paper: paper, hint: hint))
        root.isEnabled = false
        return root
    }
}

struct ScrollSystem: System {
    static let query = EntityQuery(where: .has(ScrollComponent.self))

    init(scene: RealityKit.Scene) {}

    @MainActor
    static func registerAll() {
        ScrollComponent.registerComponent()
        ScrollHandleComponent.registerComponent()
        registerSystem()
    }

    func update(context: SceneUpdateContext) {
        let deltaTime = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var state = entity.components[ScrollComponent.self] else { continue }
            let scroll = state.scroll
            scroll.update(deltaTime: deltaTime)
            let isShown = scroll.phase != .hidden && scroll.phase != .done
            if entity.isEnabled != isShown { entity.isEnabled = isShown }
            guard isShown, let pose = scroll.pose else {
                state.spot = nil
                entity.components.set(state)
                continue
            }
            let isPlaced = Self.place(entity, state: &state, deltaTime: deltaTime)
            if pose != state.shownPose {
                state.paper.show(pose)
                state.shownPose = pose
            }
            entity.components.set(OpacityComponent(opacity: isPlaced ? scroll.fade : 0))
            state.hint?.components.set(OpacityComponent(opacity: isPlaced ? 1 : 0))
            if isPlaced, let hint = state.hint {
                let rod = state.roll.rods(pose).bottom
                let below = SIMD3(0, rod.x - state.roll.radius(rolled: state.roll.rolled(pose).bottom)
                                    - ScrollComponent.hintDrop, rod.y)
                hint.setPosition(entity.convert(position: below, to: nil), relativeTo: nil)
                hint.setOrientation(entity.orientation(relativeTo: nil), relativeTo: nil)
            }
            entity.components.set(state)
        }
    }

    /// In front of the eyes, facing them; brought back there when the player looks away or moves (not while held).
    /// False while it waits for the eyes to be tracked.
    @MainActor
    private static func place(_ entity: Entity, state: inout ScrollComponent, deltaTime: Float) -> Bool {
        let isTracking = state.viewer.isTracking
        // Placed in front of the fallback's eyes: in front of the real ones as soon as they are known.
        if isTracking && !state.isPlacedFromTrackedEyes { state.spot = nil }
        if state.spot == nil && !isTracking && state.waitedForEyes < ScrollComponent.eyesWait {
            state.waitedForEyes += deltaTime
            return false
        }
        let eyes = state.viewer.viewerPose()
        var forward = SIMD3(eyes.forward.x, 0, eyes.forward.z)
        forward = simd_length(forward) > 1e-3 ? simd_normalize(forward) : SIMD3(0, 0, -1)
        let isNew = state.spot == nil
        if let spot = state.spot, !state.scroll.isDragged {
            var toSpot = spot - eyes.position
            toSpot.y = 0
            let isOutOfView = simd_length(toSpot) < 1e-3
                || acos(min(max(simd_dot(simd_normalize(toSpot), forward), -1), 1)) > ScrollComponent.lookAwayAngle
            let hasDrifted = abs(spot.y - ScrollComponent.rise - eyes.position.y) > ScrollComponent.driftTolerance
                || abs(simd_length(toSpot) - ScrollComponent.distance) > ScrollComponent.driftTolerance
            if isOutOfView || hasDrifted { state.spot = nil }
        }
        if state.spot == nil {
            state.spot = eyes.position + forward * ScrollComponent.distance + SIMD3(0, ScrollComponent.rise, 0)
            // Its front (+z) towards the player.
            state.yaw = atan2(-forward.x, -forward.z)
            state.isPlacedFromTrackedEyes = isTracking
        }
        guard let spot = state.spot else { return true }
        let target = simd_quatf(angle: state.yaw, axis: SIMD3(0, 1, 0))
        if isNew {
            entity.setPosition(spot, relativeTo: nil)
            entity.setOrientation(target, relativeTo: nil)
            return true
        }
        let blend = 1 - exp(-deltaTime * ScrollComponent.responsiveness)
        let current = entity.position(relativeTo: nil)
        if simd_distance(current, spot) > 0.0005 { entity.setPosition(current + (spot - current) * blend, relativeTo: nil) }
        entity.setOrientation(simd_slerp(entity.orientation(relativeTo: nil), target, blend), relativeTo: nil)
        return true
    }
}

private extension ScrollComponent {
    var roll: ScrollRoll { paper.roll }
}
