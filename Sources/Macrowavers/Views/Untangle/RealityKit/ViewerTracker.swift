import Foundation
import QuartzCore
import simd
#if os(visionOS)
import ARKit
#endif

/// Where the player's eyes are (the "knight"), so the dragon can look them in the face.
/// On visionOS it uses ARKit's device tracking (no permission needed);
/// when it is not available (e.g. simulator) it uses the typical eye height of a seated person.
@MainActor
final class ViewerTracker {
    /// Eyes of a seated person, at the origin of the immersive space.
    static let fallbackPosition = SIMD3<Float>(0, 1.15, 0)

    #if os(visionOS)
    private let session = ARKitSession()
    private let worldTracking = WorldTrackingProvider()
    private var isRunning = false
    #endif

    func start() async {
        #if os(visionOS)
        guard WorldTrackingProvider.isSupported, !isRunning else { return }
        do {
            try await session.run([worldTracking])
            isRunning = true
        } catch {
            print("⚠️ Head tracking unavailable: \(error)")
        }
        #endif
    }

    func stop() {
        #if os(visionOS)
        session.stop()
        isRunning = false
        #endif
    }

    /// Position of the eyes in the immersive scene's space.
    func viewerPosition() -> SIMD3<Float> {
        #if os(visionOS)
        guard isRunning, worldTracking.state == .running,
              let device = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else {
            return Self.fallbackPosition
        }
        let column = device.originFromAnchorTransform.columns.3
        return SIMD3(column.x, column.y, column.z)
        #else
        return Self.fallbackPosition
        #endif
    }
}
