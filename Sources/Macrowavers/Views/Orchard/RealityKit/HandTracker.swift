import Foundation
import simd
#if os(visionOS)
import ARKit
#endif

/// The player's hands, for the gestures SwiftUI does not offer: chopping the pineapple and snapping the fingers
/// to brew the elixir. ARKit hand tracking (asks the player's permission once); when it is not available
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
            print("⚠️ Hand tracking not allowed: taps replace the chop and the snap")
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
        // Every joint, tracked or estimated: in a fast movement (the snap) ARKit often flags the fingertips as not
        // tracked for a frame while still giving a good estimate. Dropping the whole reading then would hide
        // exactly the moment the gesture happens.
        func position(_ name: HandSkeleton.JointName) -> SIMD3<Float> {
            let transform = anchor.originFromAnchorTransform * skeleton.joint(name).anchorFromJointTransform
            return SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        }
        return HandSample(chirality: chirality, timestamp: timestamp, knuckle: position(.middleFingerKnuckle),
                          wrist: position(.wrist), thumbTip: position(.thumbTip), indexTip: position(.indexFingerTip),
                          middleDistal: position(.middleFingerIntermediateTip), middleTip: position(.middleFingerTip),
                          indexKnuckle: position(.indexFingerKnuckle), ringKnuckle: position(.ringFingerKnuckle),
                          littleKnuckle: position(.littleFingerKnuckle), ringTip: position(.ringFingerTip),
                          littleTip: position(.littleFingerTip))
    }
    #endif
}
