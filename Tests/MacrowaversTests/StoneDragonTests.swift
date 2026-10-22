import simd
import Testing
@testable import Macrowavers

struct StoneDragonLayoutTests {
    private let config = TangleConfig()

    /// A head at the origin and `count` stones along +X, `spacing` apart, the first `spacing` behind the head.
    private func layout(count: Int, spacing: Float) -> StoneDragonLayout {
        StoneDragonLayout(head: .zero, restCentres: (1...count).map { SIMD3(Float($0) * spacing, 0, 0) },
                          config: config)
    }

    @Test func stonesKeepTheirPlacesAlongTheWholeBody() {
        let stones = layout(count: 19, spacing: 1.2)
        let bodyLength = config.segmentLength * Float(config.nodeCount - 1)
        #expect(stones.arcLengths.count == 19)
        // The tail stone at the end of the body, the others evenly spaced as in the asset.
        #expect(abs(stones.arcLengths.last! - bodyLength) < 1e-4)
        #expect(abs(stones.arcLengths[0] - bodyLength / 19) < 1e-4)
        #expect(zip(stones.arcLengths, stones.arcLengths.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func everyStoneIsHeldByItsOwnNodeNextToIt() {
        let stones = layout(count: 19, spacing: 1.2)
        #expect(stones.nodes.count == 19)
        // Distinct, in order, never the head's node (the head has its own grab), within the body.
        #expect(zip(stones.nodes, stones.nodes.dropFirst()).allSatisfy { $0 < $1 })
        #expect(stones.nodes.first! >= 1 && stones.nodes.last! <= config.nodeCount - 1)
        // Each node lies under its stone: within half a segment.
        for (arc, node) in zip(stones.arcLengths, stones.nodes) {
            #expect(abs(Float(node) * config.segmentLength - arc) <= config.segmentLength / 2 + 1e-4)
        }
    }

    @Test func grabSpheresNeverReachTheNextStone() {
        let stones = StoneDragonLayout(head: .zero, restCentres: [1, 2.2, 3, 4.5].map { SIMD3(Float($0), 0, 0) },
                                       config: config)
        for index in stones.arcLengths.indices.dropLast() {
            let gap = stones.arcLengths[index + 1] - stones.arcLengths[index]
            #expect(stones.halfGap(around: index) + stones.halfGap(around: index + 1) <= gap + 1e-5)
        }
        // The asset's units to the body's metres.
        #expect(abs(stones.scale - config.segmentLength * Float(config.nodeCount - 1) / 4.5) < 1e-5)
    }

    @Test func moreStonesThanRoomStillGetDistinctNodes() {
        // 60 stones on 63 grabbable nodes: some crowd together, but the layout never shares a node or takes the head.
        let crowded = StoneDragonLayout(head: .zero, restCentres: (1...60).map { SIMD3(Float($0), 0, 0) },
                                        config: config)
        #expect(Set(crowded.nodes).count == 60)
        #expect(crowded.nodes.allSatisfy { $0 >= 1 && $0 < config.nodeCount })
    }
}
