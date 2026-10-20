import Foundation
import Observation
import simd

/// View model of the time of day: the clock running from dawn to sunset (`TimeOfDay`). It knows nothing about the
/// dragon or the fruit: `TimeOfDaySystem` tells it, every frame, the moment the game is at and lights the scene
/// from its clock. SwiftUI reads only the room's tint and the moment, which change in small steps, never every
/// frame.
@MainActor
@Observable
final class SkyViewModel {
    /// Steps of the room's tint per clock unit: smooth enough for a slow transition, few SwiftUI updates.
    static let tintSteps: Float = 64

    /// 0 dawn ... 1 sunset. Changes every frame during a transition: not observed.
    @ObservationIgnored private(set) var clock: Float = 0
    /// Debug (dragon panel): holds the clock at this point instead of following the game.
    var debugClock: Float?
    /// Colour the passthrough is multiplied by, rounded to `tintSteps`.
    private(set) var roomTint = TimeOfDay.daylight(at: 0).roomTint
    /// The moment of the day closest to the clock.
    private(set) var moment = TimeOfDay.Moment.dawn

    /// The light right now.
    var daylight: Daylight { TimeOfDay.daylight(at: clock) }

    /// One frame: the clock runs towards `target` (or the debug clock). Returns whether it moved.
    @discardableResult
    func advance(toward target: Float, deltaTime: Float) -> Bool {
        let next = TimeOfDay.advance(clock, toward: debugClock ?? target, deltaTime: deltaTime)
        guard next != clock else { return false }
        clock = next
        publish()
        return true
    }

    /// The immersive space closed: back to dawn, no debug clock.
    func reset() {
        clock = 0
        debugClock = nil
        publish()
    }

    /// Updates the observed values only when they change.
    private func publish() {
        let stepped = TimeOfDay.daylight(at: (clock * Self.tintSteps).rounded() / Self.tintSteps).roomTint
        if stepped != roomTint { roomTint = stepped }
        let nearest = TimeOfDay.Moment.nearest(to: clock)
        if nearest != moment { moment = nearest }
    }
}
