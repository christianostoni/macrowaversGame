import Foundation
import simd

/// Where smoke and fire leave the stone dragon's head, measured on its own meshes (head space: snout towards +Z, +Y
/// up; the lower jaw turns around `hinge`'s +X to open). The asset's `mouth` and `nostrils` markers sit at x = 0,
/// but the head is not centred there: the snout spans x −2.5…+6.6 cm, so they came out on its left edge.
///
/// - The snout's front: the face's vertices within `frontShare` of its depth from the tip. Its middle across is the
///   snout's centre line, its top the nose, its bottom the upper lip.
/// - The nostrils: two, either side of the centre line (`nostrilSpread` of the snout's width), a little below the
///   top of the nose (`nostrilDrop` of the snout's height), on its front.
/// - The mouth: halfway between the upper lip and the lower jaw's front edge, which turns with the jaw: the fire
///   leaves from the middle of the opening, however wide, along the snout tilted down by half the jaw's angle.
struct DragonSnout: Equatable {
    /// Share of the head's depth, from the tip, that makes the snout's front.
    static let frontShare: Float = 0.12
    static let nostrilSpread: Float = 0.22
    static let nostrilDrop: Float = 0.12
    /// How far behind the tip the openings are, as a share of the head's depth (just inside the front face).
    static let inset: Float = 0.02

    /// Left and right nostril (head space).
    let nostrils: [SIMD3<Float>]
    /// The upper lip's front (head space) and the lower jaw's front edge with the mouth closed.
    let upperLip: SIMD3<Float>
    let lowerLip: SIMD3<Float>
    let hinge: SIMD3<Float>

    /// `face`: the head's vertices without the jaw, the teeth or the horns; `jaw`: the lower jaw's, mouth closed;
    /// `hinge`: where the jaw turns. nil when either is empty.
    init?(face: [SIMD3<Float>], jaw: [SIMD3<Float>], hinge: SIMD3<Float>) {
        guard let tip = face.map(\.z).max(), let back = face.map(\.z).min(),
              let jawTip = jaw.map(\.z).max() else { return nil }
        let depth = max(tip - back, 1e-4)
        let front = face.filter { $0.z > tip - Self.frontShare * depth }
        let jawFront = jaw.filter { $0.z > jawTip - Self.frontShare * depth }
        guard let left = front.map(\.x).min(), let right = front.map(\.x).max(),
              let nose = front.map(\.y).max(), let lip = front.map(\.y).min(),
              let jawLeft = jawFront.map(\.x).min(), let jawRight = jawFront.map(\.x).max(),
              let jawTop = jawFront.map(\.y).max() else { return nil }
        let centre = (left + right) / 2
        let inset = Self.inset * depth
        let nostrilHeight = nose - Self.nostrilDrop * (nose - lip)
        let spread = Self.nostrilSpread * (right - left)
        nostrils = [SIMD3(centre - spread, nostrilHeight, tip - inset), SIMD3(centre + spread, nostrilHeight, tip - inset)]
        upperLip = SIMD3(centre, lip, tip - 2 * inset)
        lowerLip = SIMD3((jawLeft + jawRight) / 2, jawTop, jawTip - inset)
        self.hinge = hinge
    }

    /// The middle of the mouth's opening with the jaw turned `jawAngle` (radians, + opens).
    func mouth(jawAngle: Float) -> SIMD3<Float> {
        let lower = hinge + simd_quatf(angle: jawAngle, axis: SIMD3(1, 0, 0)).act(lowerLip - hinge)
        return (upperLip + lower) / 2
    }

    /// Which way the fire leaves: along the snout, tilted down by half the jaw's angle (as a rotation from +Z).
    func fireTilt(jawAngle: Float) -> simd_quatf {
        simd_quatf(angle: jawAngle / 2, axis: SIMD3(1, 0, 0))
    }
}
