import RealityKit

extension OrchardSystem {
    /// How fast a turned fruit eases back to face the player as it starts to open (1/s): most of the way in a third
    /// of a second.
    static let settleResponsiveness: Float = 10

    /// A turned pomegranate, orange or pineapple eases back to face the player as it starts to open (the first pull,
    /// the chop or the tap): its halves, wedges and cut are set in the fruit, and turned it opened away from the
    /// player. It opens meanwhile, as if the hands straightened it. Once open it can be turned again. The apple's
    /// spiral and the banana's strips look right whichever way they face: they keep the player's turn.
    @MainActor
    static func settleBeforeOpening(_ orchard: inout OrchardComponent) {
        let viewModel = orchard.viewModel
        guard let fruit = orchard.fruits.first(where: { $0.fruit.id == viewModel.focusedFruitID }) else {
            orchard.focusedIsOpening = false
            return
        }
        let isOpening = switch fruit.rig {
        case .pomegranate: viewModel.pomegranateOpening > 0
        case .orange: viewModel.orangeOpening > 0
        case .pineapple: viewModel.pineappleChopped
        case .apple, .banana: false
        }
        defer { orchard.focusedIsOpening = isOpening }
        // Still flying in, it is already on its way to face the player.
        guard isOpening, !orchard.focusedIsOpening, !fruit.holder.components.has(FocusComponent.self) else { return }
        fruit.holder.components.set(FocusComponent(target: Transform(scale: SIMD3(repeating: fruit.focusScale)),
                                                   responsiveness: settleResponsiveness))
    }
}
