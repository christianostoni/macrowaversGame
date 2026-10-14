import Foundation
import simd

/// The dragon's mood: drives both the difficulty and the animations.
enum DragonMood: Equatable {
    /// Calm, breathing and keeping an eye on the knight.
    case calm
    /// The player is pulling it.
    case annoyed
    /// No progress for too long: it is about to lose its temper.
    case restless
    /// Fit of anger: plays a sequence of `DragonAction`.
    case wriggling
    /// Free!
    case free
}

/// Moves in the dragon's repertoire during a fit of anger.
enum DragonAction: Equatable {
    /// Rears up on its neck, spreads its wings and roars at the knight. Intimidates, does not touch the tangle.
    case rearUp
    /// Turns around (radians, sign = direction). Rigid rotation: the tangle does not change.
    case turn(angle: Float)
    /// Tail lash: the tail whips over the body and creates new crossings.
    case tailLash
    /// Coils up: a middle part of the body folds over the rest.
    case coil

    var duration: Float {
        switch self {
        case .rearUp: 1.6
        case .turn(let angle): 0.9 + abs(angle) / .pi * 1.2
        case .tailLash: 1.5
        case .coil: 1.7
        }
    }

    /// The actions that change the tangle take hold of a node of the body.
    var tanglesBody: Bool {
        switch self {
        case .tailLash, .coil: true
        case .rearUp, .turn: false
        }
    }
}

struct DifficultySettings {
    /// Seconds without progress before the first fit of anger (warning included).
    var firstWriggleDelay: Float = 8
    /// Every fit shortens the wait by these seconds...
    var delayReductionPerWriggle: Float = 1
    /// ...down to this minimum.
    var minimumWriggleDelay: Float = 5
    /// For how many seconds before the fit the dragon "warns" (growing restlessness).
    var warningDuration: Float = 2
    /// Extra attempts (tail lash / coil) if the fit did not add crossings.
    var maxExtraTangles = 8
    /// Wait after the last move before counting the crossings (the body settles).
    var settleTime: Float = 0.35
    /// Radius within which the dragon stays in the play area.
    var platformRadius: Float = 0.3
}

/// The dragon's own behaviour. If the player makes no progress the dragon has a fit of anger:
/// a choreography of realistic moves (rears up, turns around, lashes its tail, coils up)
/// that gets longer and nastier with every fit.
/// It uses the same physics as the player, so the new tangle can always be solved.
final class DragonBehavior {
    let settings: DifficultySettings
    /// Completed fits of anger: they raise the difficulty.
    private(set) var fitCount = 0
    /// 0...1: how close the next fit is (1 = about to happen).
    private(set) var restlessness: Float = 0
    /// Current action and its progress (0...1), for the animations.
    private(set) var currentAction: DragonAction?
    private(set) var actionProgress: Float = 0

    var isWriggling: Bool { currentAction != nil || settleRemaining != nil }

    private var queue: [DragonAction] = []
    /// Crossings at the start of the fit: at the end there must be more.
    private var crossingsAtFitStart = 0
    private var latestCrossings = 0
    private var extraTangles = 0
    /// Settling countdown before the final check (nil = not checking).
    private var settleRemaining: Float?
    private var actionElapsed: Float = 0
    private var timeWithoutProgress: Float = 0
    private var bestCrossings = Int.max
    // State of the current action.
    private var grabbedNode: Int?
    private var from = SIMD3<Float>.zero
    private var to = SIMD3<Float>.zero
    private var pivot = SIMD3<Float>.zero
    private var appliedTurn: Float = 0
    private var random = SystemRandomNumberGenerator()

    init(settings: DifficultySettings = DifficultySettings()) {
        self.settings = settings
    }

    var currentDelay: Float {
        max(settings.minimumWriggleDelay,
            settings.firstWriggleDelay - Float(fitCount) * settings.delayReductionPerWriggle)
    }

    func reset() {
        fitCount = 0
        restlessness = 0
        timeWithoutProgress = 0
        bestCrossings = .max
        queue = []
        currentAction = nil
        grabbedNode = nil
        settleRemaining = nil
        extraTangles = 0
    }

    /// The player grabs the dragon during the fit: the dragon stops and lets go.
    func interrupt(_ simulation: TangleSimulation) {
        guard isWriggling else { return }
        if let grabbedNode { simulation.release(grabbedNode) }
        queue = []
        settleRemaining = nil
        finishFit()
    }

    func update(deltaTime: Float, crossings: Int, userIsGrabbing: Bool, simulation: TangleSimulation) {
        latestCrossings = crossings
        if currentAction != nil {
            continueAction(deltaTime: deltaTime, simulation: simulation)
            return
        }
        if let remaining = settleRemaining {
            settleRemaining = remaining - deltaTime
            if remaining - deltaTime <= 0 { checkFitResult(simulation) }
            return
        }

        // Progress = a new lowest crossing count.
        if crossings < bestCrossings {
            bestCrossings = crossings
            timeWithoutProgress = 0
        } else {
            timeWithoutProgress += deltaTime
        }

        let warningStart = currentDelay - settings.warningDuration
        restlessness = max(0, min(1, (timeWithoutProgress - warningStart) / settings.warningDuration))

        // It never tears the dragon out of the player's hands: it waits until they let go.
        if timeWithoutProgress >= currentDelay && !userIsGrabbing {
            queue = choreography()
            crossingsAtFitStart = crossings
            extraTangles = 0
            restlessness = 0
            startNextAction(simulation)
        }
    }

    /// The fit must leave the dragon more tangled than before: if not, it tries again.
    private func checkFitResult(_ simulation: TangleSimulation) {
        settleRemaining = nil
        if latestCrossings > crossingsAtFitStart || extraTangles >= settings.maxExtraTangles {
            finishFit()
            return
        }
        extraTangles += 1
        // Alternates the two moves, so the next attempt starts from a different part.
        queue = [extraTangles.isMultiple(of: 2) ? .coil : .tailLash]
        startNextAction(simulation)
    }

    // MARK: - Choreography

    /// Sequence of the fit: the more fits it has had, the longer it is.
    /// It always starts by turning around (immediate reaction), then intimidates and tangles.
    private func choreography() -> [DragonAction] {
        let direction: Float = Bool.random(using: &random) ? 1 : -1
        let turn = DragonAction.turn(angle: direction * Float.random(in: (.pi * 0.5)...(.pi * 0.9), using: &random))
        switch fitCount {
        case 0:
            return [turn, .tailLash]
        case 1:
            return [turn, .rearUp, .tailLash]
        default:
            let tangle: [DragonAction] = Bool.random(using: &random) ? [.tailLash, .coil] : [.coil, .tailLash]
            return [turn, .rearUp] + tangle + [.turn(angle: -direction * .pi * 0.4)]
        }
    }

    private func startNextAction(_ simulation: TangleSimulation) {
        guard !queue.isEmpty else {
            // End of the choreography: let the body settle, then check that there are more crossings.
            currentAction = nil
            actionProgress = 0
            settleRemaining = settings.settleTime
            return
        }
        let action = queue.removeFirst()
        currentAction = action
        actionElapsed = 0
        actionProgress = 0
        grabbedNode = nil

        switch action {
        case .rearUp:
            break
        case .turn:
            pivot = simulation.centroid
            appliedTurn = 0
        case .tailLash:
            beginCrossing(node: simulation.positions.count - 1, simulation: simulation)
        case .coil:
            // A part between the middle of the body and the tail, different at every attempt.
            let count = Float(simulation.positions.count)
            beginCrossing(node: Int(count * Float.random(in: 0.55...0.8, using: &random)), simulation: simulation)
        }
        // If it cannot grab the node, it moves on.
        if action.tanglesBody && grabbedNode == nil { startNextAction(simulation) }
    }

    /// Prepares a part of the body to step over another specific part and land just past it:
    /// the dragged part passes over it and a new crossing is born.
    private func beginCrossing(node: Int, simulation: TangleSimulation) {
        let positions = simulation.positions
        let start = positions[node]
        let flatStart = SIMD2(start.x, start.z)
        let reach: ClosedRange<Float> = 0.06...0.28
        let beyond = simulation.config.radius * 3

        // Parts far along the body but within reach, with the landing point inside the play area.
        var candidates: [SIMD2<Float>] = []
        for segment in 0..<(positions.count - 1) where abs(segment - node) > 6 {
            let middle = (positions[segment] + positions[segment + 1]) / 2
            let flatMiddle = SIMD2(middle.x, middle.z)
            let distance = simd_length(flatMiddle - flatStart)
            guard reach.contains(distance) else { continue }
            let landing = flatMiddle + (flatMiddle - flatStart) / distance * beyond
            if simd_length(landing) <= settings.platformRadius { candidates.append(landing) }
        }

        var target: SIMD2<Float>
        if let landing = candidates.randomElement(using: &random) {
            target = landing
        } else {
            // No suitable part: goes "to the other side" of the body's centre.
            let center = simulation.centroid
            target = SIMD2(2 * center.x - start.x, 2 * center.z - start.z)
            if simd_length(target) > settings.platformRadius {
                target = simd_normalize(target) * settings.platformRadius
            }
        }
        guard simulation.grab(node) else { return }
        grabbedNode = node
        from = start
        to = SIMD3(target.x, simulation.config.grabLift, target.y)
    }

    private func continueAction(deltaTime: Float, simulation: TangleSimulation) {
        guard let action = currentAction else { return }
        actionElapsed += deltaTime
        let progress = min(actionElapsed / action.duration, 1)
        actionProgress = progress
        let eased = progress * progress * (3 - 2 * progress)

        switch action {
        case .rearUp:
            break
        case .turn(let angle):
            // Progressive rotation: starts slowly, speeds up, slows down (like a heavy body).
            let target = angle * eased
            simulation.rotateBody(by: target - appliedTurn, around: pivot)
            appliedTurn = target
        case .tailLash, .coil:
            guard let node = grabbedNode else { break }
            // Arc with a sideways wave: it looks like the crack of a whip.
            let side = SIMD3(-(to.z - from.z), 0, to.x - from.x)
            var point = simd_mix(from, to, SIMD3(repeating: eased)) + side * (0.25 * sin(progress * .pi * 2))
            point.y = simulation.config.grabLift
            simulation.drag(node, to: point)
        }

        if progress >= 1 {
            if let grabbedNode { simulation.release(grabbedNode) }
            grabbedNode = nil
            startNextAction(simulation)
        }
    }

    private func finishFit() {
        currentAction = nil
        actionProgress = 0
        grabbedNode = nil
        fitCount += 1
        timeWithoutProgress = 0
        // The new tangle becomes the reference: undoing what it just did counts as progress.
        bestCrossings = .max
    }
}
