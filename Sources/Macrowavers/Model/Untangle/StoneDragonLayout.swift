import Foundation
import simd

/// Where the stone dragon's stones sit along the simulated body, and which node each one is held by.
/// Pure maths (Foundation + simd): the `StoneDragonRig` builds one from the asset's rest pose.
///
/// The asset is a head and a chain of separate stones. Each stone keeps its distance from the head along the body,
/// scaled to the simulated body's length, and is held by the node closest to it: grabbing a stone grabs that
/// node, so every stone can untangle the dragon. The nodes between the stones carry no grab of their own.
struct StoneDragonLayout: Equatable {
    /// Distance of each stone's centre from the head along the simulated body (m), from the head to the tail.
    let arcLengths: [Float]
    /// The node holding each stone: increasing, distinct, never the head's (node 0, held by the head itself).
    let nodes: [Int]
    /// From the asset's units to the simulated body's metres: the stones keep the design's proportions at this scale.
    let scale: Float

    /// - Parameters:
    ///   - head: the head's centre in the asset's rest pose.
    ///   - restCentres: the stones' centres in the rest pose, from the head to the tail.
    init(head: SIMD3<Float>, restCentres: [SIMD3<Float>], config: TangleConfig) {
        var travelled: Float = 0
        var previous = head
        var restArcs: [Float] = []
        for centre in restCentres {
            travelled += simd_length(centre - previous)
            restArcs.append(travelled)
            previous = centre
        }
        let bodyLength = config.segmentLength * Float(config.nodeCount - 1)
        let scale = travelled > 1e-6 ? bodyLength / travelled : 0
        self.scale = scale
        arcLengths = restArcs.map { $0 * scale }

        // The closest node, kept in order and one per stone, room left for the stones still to come.
        let lastNode = config.nodeCount - 1
        var nodes: [Int] = []
        for (index, arc) in arcLengths.enumerated() {
            let closest = Int((arc / config.segmentLength).rounded())
            let earliest = (nodes.last ?? 0) + 1
            let latest = lastNode - (arcLengths.count - 1 - index)
            nodes.append(min(max(closest, earliest), latest))
        }
        self.nodes = nodes
    }

    /// Half the distance from the head to the first stone (m): the head's grab sphere never reaches the stone's.
    var headHalfGap: Float { 0.5 * (arcLengths.first ?? 0) }

    /// Half the distance from stone `index` to its closest neighbour along the body (m): a grab sphere of that
    /// radius never reaches the next stone's.
    func halfGap(around index: Int) -> Float {
        let before = index > 0 ? arcLengths[index] - arcLengths[index - 1] : arcLengths[index]
        let after = index + 1 < arcLengths.count ? arcLengths[index + 1] - arcLengths[index] : before
        return 0.5 * min(before, after)
    }
}
