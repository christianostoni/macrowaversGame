import Foundation
import simd

/// The hologram hand's skins (`HandSurface`), one per distinct pose of its loop, baked ahead of time into a resource
/// (`SnapHintHand.bin`, made by `Assets/SnapHint/make_snap_hint_hand.sh`).
/// Pure Foundation + simd: the script bakes it, `SnapHintRig` reads it.
///
/// The skins cost ~0.3 s of processor time in an optimised build but ~20 s in a Debug one (unoptimised Swift is
/// ~65 times slower at this maths), and far more on the headset's background threads: built at run time, the hand
/// showed up long after the orbit was complete. Read from the resource, they are only decompressed and copied.
///
/// Each skin carries the signature of its pose (`HandSurface.signature`): if `SnapHint` or `HandSurface` changes and
/// the resource is not baked again, it no longer matches the code (`matchesCode`) and the rig builds the skins itself.
///
/// The file, LZFSE-compressed, little-endian: "SNAP", version, frames per second, frame count, each frame's skin
/// (UInt16), skin count, signature length; then each skin: its signature (Float32), vertex and index counts (UInt32),
/// positions and normals (Float16 × 3) and indices (UInt32).
struct SnapHintBake: Equatable {
    struct Skin: Equatable {
        var signature: [Float]
        var mesh: HandSurface.Mesh
    }

    enum DecodingError: Error {
        case compression
        case format
    }

    static let resourceName = "SnapHintHand"
    static let resourceExtension = "bin"
    private static let magic: UInt32 = 0x50414E53 // "SNAP"
    private static let version: UInt32 = 1
    /// How far a signature may drift from the code's and still match (m): float rounding, not a change of pose.
    static let tolerance: Float = 1e-5
    /// Frames of the loop with a skin of their own (the snap itself lasts ~4).
    static let framesPerSecond: Float = 30
    static var frameCount: Int { Int((SnapHint.period * framesPerSecond).rounded(.up)) }

    let framesPerSecond: Float
    /// The skin each frame of the loop shows.
    let frames: [Int]
    let skins: [Skin]

    /// The loop's distinct poses, and which one each frame shows (a frame that holds the previous pose shares its
    /// skin).
    static func loop() -> (poses: [SnapHint.Pose], frames: [Int]) {
        var poses: [SnapHint.Pose] = []
        var frames: [Int] = []
        for frame in 0..<frameCount {
            let pose = SnapHint.pose(at: Float(frame) / framesPerSecond)
            if pose != poses.last { poses.append(pose) }
            frames.append(poses.count - 1)
        }
        return (poses, frames)
    }

    /// Builds every skin of the loop (slow: for the script, optimised).
    static func bake() -> SnapHintBake {
        let loop = loop()
        let skins = loop.poses.map { pose in
            let surface = HandSurface(pose: pose)
            return Skin(signature: surface.signature, mesh: surface.mesh())
        }
        return SnapHintBake(framesPerSecond: framesPerSecond, frames: loop.frames, skins: skins)
    }

    init(framesPerSecond: Float, frames: [Int], skins: [Skin]) {
        self.framesPerSecond = framesPerSecond
        self.frames = frames
        self.skins = skins
    }

    /// The baked skins are the ones the code would build: every frame's pose has its skin's signature. Cheap: poses
    /// only, no skin.
    var matchesCode: Bool {
        guard framesPerSecond == Self.framesPerSecond, frames.count == Self.frameCount,
              frames.allSatisfy(skins.indices.contains) else { return false }
        for (frame, skin) in frames.enumerated() {
            let signature = HandSurface(pose: SnapHint.pose(at: Float(frame) / Self.framesPerSecond)).signature
            let baked = skins[skin].signature
            guard signature.count == baked.count,
                  zip(signature, baked).allSatisfy({ abs($0 - $1) <= Self.tolerance }) else { return false }
        }
        return true
    }

    // MARK: - File

    func encoded() throws -> Data {
        var data = Data()
        data.appendValue(Self.magic)
        data.appendValue(Self.version)
        data.appendValue(framesPerSecond.bitPattern)
        data.appendValue(UInt32(frames.count))
        data.appendValues(frames.map(UInt16.init))
        data.appendValue(UInt32(skins.count))
        data.appendValue(UInt32(skins.first?.signature.count ?? 0))
        for skin in skins {
            data.appendValues(skin.signature)
            data.appendValue(UInt32(skin.mesh.positions.count))
            data.appendValue(UInt32(skin.mesh.indices.count))
            data.appendValues(Self.halves(skin.mesh.positions))
            data.appendValues(Self.halves(skin.mesh.normals))
            data.appendValues(skin.mesh.indices)
        }
        return try (data as NSData).compressed(using: .lzfse) as Data
    }

    init(data compressed: Data) throws {
        guard let data = try? (compressed as NSData).decompressed(using: .lzfse) as Data else {
            throw DecodingError.compression
        }
        var reader = Reader(data: data)
        guard try reader.read(UInt32.self) == Self.magic, try reader.read(UInt32.self) == Self.version else {
            throw DecodingError.format
        }
        framesPerSecond = Float(bitPattern: try reader.read(UInt32.self))
        let frameCount = Int(try reader.read(UInt32.self))
        frames = try reader.read(UInt16.self, count: frameCount).map(Int.init)
        let skinCount = Int(try reader.read(UInt32.self))
        let signatureLength = Int(try reader.read(UInt32.self))
        var skins: [Skin] = []
        for _ in 0..<skinCount {
            let signature = try reader.read(Float.self, count: signatureLength)
            let vertexCount = Int(try reader.read(UInt32.self))
            let indexCount = Int(try reader.read(UInt32.self))
            let positions = Self.vectors(try reader.read(Float16.self, count: 3 * vertexCount))
            let normals = Self.vectors(try reader.read(Float16.self, count: 3 * vertexCount))
            let indices = try reader.read(UInt32.self, count: indexCount)
            guard indices.allSatisfy({ $0 < vertexCount }) else { throw DecodingError.format }
            skins.append(Skin(signature: signature,
                              mesh: HandSurface.Mesh(positions: positions, normals: normals, indices: indices)))
        }
        guard reader.isAtEnd else { throw DecodingError.format }
        self.skins = skins
    }

    private static func halves(_ vectors: [SIMD3<Float>]) -> [Float16] {
        vectors.flatMap { [Float16($0.x), Float16($0.y), Float16($0.z)] }
    }

    private static func vectors(_ halves: [Float16]) -> [SIMD3<Float>] {
        (0..<halves.count / 3).map { SIMD3(Float(halves[3 * $0]), Float(halves[3 * $0 + 1]), Float(halves[3 * $0 + 2])) }
    }

    /// Reads plain values off the front of the file, in order.
    private struct Reader {
        let data: Data
        private var offset = 0

        init(data: Data) {
            self.data = data
        }

        var isAtEnd: Bool { offset == data.count }

        mutating func read<Value>(_ type: Value.Type) throws -> Value {
            try read(type, count: 1)[0]
        }

        mutating func read<Value>(_: Value.Type, count: Int) throws -> [Value] {
            let size = MemoryLayout<Value>.stride * count
            guard count >= 0, offset + size <= data.count else { throw DecodingError.format }
            let values = [Value](unsafeUninitializedCapacity: count) { buffer, initialised in
                data.withUnsafeBytes { bytes in
                    UnsafeMutableRawBufferPointer(buffer).copyMemory(from: UnsafeRawBufferPointer(
                        rebasing: bytes[offset..<offset + size]))
                }
                initialised = count
            }
            offset += size
            return values
        }
    }
}

private extension Data {
    mutating func appendValue<Value>(_ value: Value) {
        appendValues([value])
    }

    mutating func appendValues<Value>(_ values: [Value]) {
        values.withUnsafeBytes { append(contentsOf: $0) }
    }
}

extension HandSurface {
    /// Every number the skin depends on: its bones (ends, radii) and its shape's constants. Two hands with the same
    /// signature have the same skin.
    var signature: [Float] {
        let cones = [thenar] + thumb + fingers.flatMap { $0 }
        let bones = cones.flatMap { cone in
            [cone.start.x, cone.start.y, cone.start.z, cone.end.x, cone.end.y, cone.end.z,
             cone.startRadius, cone.endRadius]
        }
        let shape = [Self.cellSize, Self.palmBlend, Self.fingerBlend, Self.palmCentre.x, Self.palmCentre.y,
                     Self.palmCentre.z, Self.palmHalfHeight, Self.palmHalfThickness, Self.palmRounding,
                     Self.wristHalfWidth, Self.palmWidening, Self.taper.x, Self.taper.y, Self.taper.z]
        return bones + shape
    }
}
