import Foundation
import simd
#if os(visionOS)
import ARKit
#endif

/// The player's hands, for the gestures SwiftUI does not offer: chopping the pineapple and twisting the pinched
/// fingers at the kalash. ARKit hand tracking (asks the player's permission once); when it is not available
/// (simulator, permission denied) `start()` returns false and the taps take over.
@MainActor
final class HandTracker {
    /// Latest reading of each hand still tracked.
    private(set) var samples: [HandSample.Chirality: HandSample] = [:]

    #if os(visionOS)
    private let session = ARKitSession()
    private let handTracking = HandTrackingProvider()
    private var isRunning = false
    #endif

    /// Starts the tracking; returns whether it runs.
    func start() async -> Bool {
        #if os(visionOS)
        guard HandTrackingProvider.isSupported else { return false }
        guard !isRunning else { return true }
        let authorization = await session.requestAuthorization(for: HandTrackingProvider.requiredAuthorizations)
        guard !authorization.values.contains(.denied) else {
            print("⚠️ Hand tracking not allowed: taps replace the chop and the twist")
            return false
        }
        do {
            try await session.run([handTracking])
            isRunning = true
            return true
        } catch {
            print("⚠️ Hand tracking unavailable: \(error)")
            return false
        }
        #else
        return false
        #endif
    }

    /// Reads the hands until the tracking stops (call from the view's `.task`, after `start()`).
    func track() async {
        #if os(visionOS)
        guard isRunning else { return }
        for await update in handTracking.anchorUpdates {
            let anchor = update.anchor
            let chirality: HandSample.Chirality = anchor.chirality == .left ? .left : .right
            samples[chirality] = Self.sample(from: anchor, chirality: chirality, timestamp: update.timestamp)
        }
        #endif
    }

    func stop() {
        #if os(visionOS)
        session.stop()
        isRunning = false
        #endif
        samples = [:]
    }

    #if os(visionOS)
    private static func sample(from anchor: HandAnchor, chirality: HandSample.Chirality,
                               timestamp: TimeInterval) -> HandSample? {
        guard anchor.isTracked, let skeleton = anchor.handSkeleton else { return nil }
        func position(_ name: HandSkeleton.JointName) -> SIMD3<Float>? {
            let joint = skeleton.joint(name)
            guard joint.isTracked else { return nil }
            let transform = anchor.originFromAnchorTransform * joint.anchorFromJointTransform
            return SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        }
        guard let wrist = position(.wrist), let knuckle = position(.middleFingerKnuckle),
              let thumbTip = position(.thumbTip), let indexTip = position(.indexFingerTip),
              let indexKnuckle = position(.indexFingerKnuckle), let littleKnuckle = position(.littleFingerKnuckle) else {
            return nil
        }
        // The palm's plane goes through the wrist and the knuckles: its normal rolls with the wrist.
        let normal = simd_cross(indexKnuckle - wrist, littleKnuckle - wrist)
        guard simd_length(normal) > 1e-6 else { return nil }
        return HandSample(chirality: chirality, timestamp: timestamp, knuckle: knuckle, wrist: wrist,
                          thumbTip: thumbTip, indexTip: indexTip, palmNormal: simd_normalize(normal))
    }
    #endif
}
