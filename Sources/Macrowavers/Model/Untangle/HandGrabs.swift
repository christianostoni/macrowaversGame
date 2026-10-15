import Foundation

/// Which hand holds which node of the dragon's body, rebuilt from the manipulation events of each node's
/// collider (one `ManipulationComponent` per node, so each hand drives its own node).
///
/// The events are not a clean begin/end pair per hand, so the rules are explicit:
/// - a hand holds one node at a time: when it starts a new grab, a node it was still recorded on is let go
///   (its release was missed), instead of staying frozen in the simulation;
/// - a node can pass from one hand to the other, or be held by both, without being let go (`handedOff`);
/// - a release is followed by an end event. A quick re-grab of the same node can arrive between the two:
///   that late end must not let go of the new grab. An end with no release before it is a cancelled grab.
struct HandGrabs: Equatable {
    enum Hand: Hashable {
        case left
        case right
        /// No chirality (e.g. a pointer in the simulator): never assumed to be the same hand as another.
        case unknown
    }

    /// What the simulation has to do.
    enum Change: Equatable {
        case grab(Int)
        case release(Int)
    }

    /// Hands on each held node.
    private(set) var holders: [Int: Set<Hand>] = [:]
    /// End events still expected after a release, per node.
    private var pendingEnds: [Int: Int] = [:]

    var heldNodes: Set<Int> { Set(holders.keys) }

    func node(heldBy hand: Hand) -> Int? {
        guard hand != .unknown else { return nil }
        return holders.first { $0.value.contains(hand) }?.key
    }

    /// A manipulation started on `node`.
    mutating func began(node: Int, hands: Set<Hand>) -> [Change] {
        var changes = takeHands(hands, for: node)
        if holders[node] == nil { changes.append(.grab(node)) }
        holders[node] = hands.isEmpty ? [.unknown] : hands
        return changes
    }

    /// The hands on `node` changed (from one hand to the other, or a second hand joined or left).
    mutating func handedOff(node: Int, to hands: Set<Hand>) -> [Change] {
        guard holders[node] != nil else { return [] }
        guard !hands.isEmpty else {
            holders[node] = nil
            return [.release(node)]
        }
        let changes = takeHands(hands, for: node)
        holders[node] = hands
        return changes
    }

    /// The hands let go of `node` (or the grab was cancelled).
    mutating func released(node: Int) -> [Change] {
        pendingEnds[node, default: 0] += 1
        guard holders.removeValue(forKey: node) != nil else { return [] }
        return [.release(node)]
    }

    /// The manipulation of `node` is over.
    mutating func ended(node: Int) -> [Change] {
        if let pending = pendingEnds[node], pending > 0 {
            // The end of a grab already released: a newer grab of the same node may be in progress.
            pendingEnds[node] = pending > 1 ? pending - 1 : nil
            return []
        }
        // Ended without a release: cancelled.
        guard holders.removeValue(forKey: node) != nil else { return [] }
        return [.release(node)]
    }

    mutating func reset() {
        holders = [:]
        pendingEnds = [:]
    }

    /// Debug text: which node each hand holds.
    var summary: String {
        guard !holders.isEmpty else { return "none" }
        return holders.keys.sorted().map { node in
            let hands = holders[node, default: []].map { hand in
                switch hand {
                case .left: "L"
                case .right: "R"
                case .unknown: "?"
                }
            }.sorted().joined(separator: "+")
            return "\(hands) \(node)"
        }.joined(separator: " · ")
    }

    /// A hand that grabs `node` lets go of any other node it was recorded on.
    private mutating func takeHands(_ hands: Set<Hand>, for node: Int) -> [Change] {
        var changes: [Change] = []
        for hand in hands where hand != .unknown {
            guard let old = self.node(heldBy: hand), old != node, var remaining = holders[old] else { continue }
            remaining.remove(hand)
            if remaining.isEmpty {
                holders[old] = nil
                changes.append(.release(old))
            } else {
                holders[old] = remaining
            }
        }
        return changes
    }
}
