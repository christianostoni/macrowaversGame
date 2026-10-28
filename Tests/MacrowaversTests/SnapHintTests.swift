import Foundation
import simd
import Testing
@testable import Macrowavers

/// The hologram hand at `time` into its loop, read like a tracked right hand (hand space is metres, as ARKit's).
private func sample(_ time: Float, at timestamp: TimeInterval) -> HandSample {
    let pose = SnapHint.pose(at: time)
    let knuckles = SnapHint.fingers.map(\.knuckle)
    return HandSample(chirality: .right, timestamp: timestamp, knuckle: knuckles[1], wrist: .zero,
                      thumbTip: pose.thumbTip, indexTip: pose.fingers[0][2], middleDistal: pose.fingers[1][1],
                      middleTip: pose.fingers[1][2], indexKnuckle: knuckles[0], ringKnuckle: knuckles[2],
                      littleKnuckle: knuckles[3], ringTip: pose.fingers[2][2], littleTip: pose.fingers[3][2])
}

@Suite struct SnapHintTests {
    @Test func theThumbPressesOnTheMiddleFingersPadWhenLoaded() {
        let pose = SnapHint.pose(at: 1.1)
        // Touching: the thumb's tip one thumb radius off the pad's surface.
        #expect(abs(simd_distance(pose.thumbTip, pose.middlePad) - SnapHint.thumbTipRadius) < 0.001)
        // Open, the thumb is far from it.
        let open = SnapHint.pose(at: 0.1)
        #expect(simd_distance(open.thumbTip, open.middlePad) > 0.08)
    }

    @Test func theMiddleFingerFlicksIntoThePalm() {
        let loaded = SnapHint.pose(at: 1.1)
        let snapped = SnapHint.pose(at: 1.5)
        #expect(simd_length(snapped.middleTip) < simd_length(loaded.middleTip) - 0.02)
        #expect(simd_distance(snapped.thumbTip, snapped.middleTip) > simd_distance(loaded.thumbTip, loaded.middleTip))
    }

    @Test func everyPoseIsFinite() {
        for step in 0...56 {
            let pose = SnapHint.pose(at: Float(step) * 0.05)
            let points = pose.fingers.flatMap { $0 } + [pose.thumb.base, pose.thumb.joint, pose.thumb.tip]
            #expect(points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        }
    }

    /// The hologram teaches the snap the game reads: its loaded and snapped poses, a frame apart at hand-tracking
    /// speed, are a snap for `SnapDetector`.
    @Test func theHologramsSnapIsOneTheDetectorAccepts() {
        var detector = SnapDetector()
        let loaded = detector.process(sample(1.1, at: 10))
        #expect(!loaded)
        #expect(detector.isLoaded)
        let snapped = detector.process(sample(SnapHint.snapTime, at: 10.05))
        #expect(snapped, "\(String(describing: detector.lastAttempt))")
    }

    @Test func itSnapsOncePerLoopAndStartsOverWhenShownAgain() {
        var hint = SnapHint()
        var snaps = 0
        for _ in 0..<Int(SnapHint.period * 2 * 90) {
            hint.update(deltaTime: 1.0 / 90.0, isShown: true)
            if hint.didSnap { snaps += 1 }
        }
        #expect(snaps == 2)
        #expect(hint.presence == 1)

        for _ in 0..<90 { hint.update(deltaTime: 1.0 / 90.0, isShown: false) }
        #expect(hint.presence == 0)
        #expect(!hint.didSnap)
        hint.update(deltaTime: 1.0 / 90.0, isShown: true)
        #expect(hint.time < 0.02)
    }
}

@Suite struct HandSurfaceTests {
    @Test func theSkinWrapsTheHandAndKeepsTheFingersApart() {
        let pose = SnapHint.pose(at: 0.1)
        let skin = HandSurface(pose: pose)
        // Inside the palm and inside a fingertip; outside, far from the hand.
        #expect(skin.distance(SIMD3(0, 0.05, 0)) < -0.005)
        #expect(skin.distance(pose.fingers[1][2]) < 0)
        #expect(skin.distance(SIMD3(0, 0.05, 0.1)) > 0.05)
        // Between two fingertips, far from the palm, the fingers do not melt into each other (no webbing): the
        // skin is just the nearer finger.
        let between = (pose.fingers[1][2] + pose.fingers[2][2]) / 2
        let nearest = skin.fingers.map { cones in cones.map { $0.distance(between) }.min() ?? .infinity }.min() ?? 0
        #expect(abs(skin.distance(between) - nearest) < 1e-6)
        // Each phalanx tapers: the fingertip is thinner than the knuckle.
        let cones = skin.fingers[1]
        #expect(cones[2].endRadius < cones[0].startRadius)
    }

    @Test func theMeshIsOneSmoothSkinFacingOut() {
        let pose = SnapHint.pose(at: 1.1)
        let skin = HandSurface(pose: pose)
        let mesh = skin.mesh()
        #expect(mesh.positions.count > 2_000 && mesh.positions.count < 20_000)
        #expect(mesh.normals.count == mesh.positions.count)
        #expect(mesh.indices.count % 3 == 0)
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count })
        // Every vertex on the skin (within a fraction of the grid step; the farthest sit in the blended creases).
        #expect(mesh.positions.allSatisfy { abs(skin.distance($0)) < HandSurface.cellSize * 0.6 })
        // Triangles wound counter-clockwise seen from outside: their face normal agrees with the vertex normals.
        var outward = 0
        for index in stride(from: 0, to: mesh.indices.count, by: 3) {
            let corners = (0..<3).map { Int(mesh.indices[index + $0]) }
            let face = simd_cross(mesh.positions[corners[1]] - mesh.positions[corners[0]],
                                  mesh.positions[corners[2]] - mesh.positions[corners[0]])
            if simd_dot(face, corners.map { mesh.normals[$0] }.reduce(.zero, +)) > 0 { outward += 1 }
        }
        #expect(Float(outward) > 0.99 * Float(mesh.indices.count / 3))
        // Closed, no holes: every edge shared by two triangles (four where two parts of the skin touch, the thumb
        // on the middle finger).
        var edges: [SIMD2<UInt32>: Int] = [:]
        for index in stride(from: 0, to: mesh.indices.count, by: 3) {
            for side in 0..<3 {
                let first = mesh.indices[index + side]
                let second = mesh.indices[index + (side + 1) % 3]
                edges[SIMD2(min(first, second), max(first, second)), default: 0] += 1
            }
        }
        #expect(edges.values.allSatisfy { $0 == 2 || $0 == 4 })
    }
}

@Suite struct SnapHintBakeTests {
    /// The resource the app ships is the skins the code builds: if this fails, run
    /// `sh Assets/SnapHint/make_snap_hint_hand.sh` (the app would build them itself, slowly).
    @Test func theBakedHandMatchesTheCode() throws {
        let url = try #require(Bundle.main.url(forResource: SnapHintBake.resourceName,
                                               withExtension: SnapHintBake.resourceExtension))
        let bake = try SnapHintBake(data: Data(contentsOf: url))
        #expect(bake.matchesCode)
        #expect(bake.frames == SnapHintBake.loop().frames)
        // One skin, rebuilt here, is the baked one (to Float16 precision: a twentieth of a millimetre).
        let skin = try #require(bake.skins.last)
        let mesh = HandSurface(pose: try #require(SnapHintBake.loop().poses.last)).mesh()
        #expect(mesh.indices == skin.mesh.indices)
        #expect(zip(mesh.positions, skin.mesh.positions).allSatisfy { simd_distance($0, $1) < 1e-4 })
    }

    @Test func aChangedPoseNoLongerMatches() {
        let loop = SnapHintBake.loop()
        let skins = loop.poses.map { pose in
            SnapHintBake.Skin(signature: HandSurface(pose: pose).signature, mesh: HandSurface.Mesh())
        }
        #expect(SnapHintBake(framesPerSecond: SnapHintBake.framesPerSecond, frames: loop.frames, skins: skins)
            .matchesCode)
        var moved = skins
        moved[0].signature[0] += 0.001
        #expect(!SnapHintBake(framesPerSecond: SnapHintBake.framesPerSecond, frames: loop.frames, skins: moved)
            .matchesCode)
    }

    @Test func theFileRoundTrips() throws {
        let mesh = HandSurface.Mesh(positions: [SIMD3(0, 0.1, 0), SIMD3(0.05, 0, -0.02), SIMD3(-0.03, 0.2, 0.01)],
                                    normals: [SIMD3(0, 0, 1), SIMD3(1, 0, 0), SIMD3(0, 1, 0)], indices: [0, 1, 2])
        let bake = SnapHintBake(framesPerSecond: 30, frames: [0, 0, 1],
                                skins: [.init(signature: [1, 2], mesh: mesh), .init(signature: [3, 4], mesh: mesh)])
        let read = try SnapHintBake(data: bake.encoded())
        #expect(read.frames == bake.frames)
        #expect(read.framesPerSecond == 30)
        #expect(read.skins.map(\.signature) == [[1, 2], [3, 4]])
        #expect(read.skins[1].mesh.indices == [0, 1, 2])
        #expect(zip(read.skins[1].mesh.positions, mesh.positions).allSatisfy { simd_distance($0, $1) < 1e-4 })
        #expect(throws: SnapHintBake.DecodingError.self) { try SnapHintBake(data: Data([1, 2, 3])) }
    }
}
