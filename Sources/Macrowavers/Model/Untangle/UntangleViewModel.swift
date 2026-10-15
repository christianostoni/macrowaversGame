import Foundation
import Observation
import simd

/// View model of the dragon's story: captive on the island, soothed by the artifact, untangled, free.
/// Exposes to the views the state to show and the player's actions; it knows neither RealityKit nor SwiftUI.
@MainActor
@Observable
final class UntangleViewModel {
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    // MARK: - State for the views

    var immersiveSpaceState = ImmersiveSpaceState.closed
    /// The dragon panel is shown in the immersive space (it opens when the dragon is tapped).
    var isDragonPanelVisible = false
    /// Current chapter of the story.
    private(set) var phase = DragonPhase.captive
    private(set) var crossingCount = 0
    var isSolved: Bool { phase == .free || phase == .gone }
    private(set) var mood = DragonMood.calm
    /// 0...1: the dragon is about to thrash.
    private(set) var restlessness: Float = 0
    /// 0...1: how taut the body is while the player pulls.
    private(set) var strain: Float = 0
    private(set) var placement = PlayAreaPlacement.seated
    /// Move in progress during a fit of anger (nil = none).
    private(set) var action: DragonAction?
    /// Untangled, the dragon has taken off.
    private(set) var isFlying = false
    /// Placement and rotation of the island (the player spins it).
    private(set) var islandPlacement = IslandPlacement.standard
    /// Which hand holds which node (from the manipulation events; shown in the debug info).
    private(set) var handGrabs = HandGrabs()

    // MARK: - Model

    @ObservationIgnored private(set) var simulation: TangleSimulation
    @ObservationIgnored let shape: TangleShape
    @ObservationIgnored private let behavior: DragonBehavior
    /// Nodes held by the player (one per hand).
    @ObservationIgnored private(set) var userGrabbedNodes: Set<Int> = []
    /// Grab order: the head looks at the first grabbed node.
    @ObservationIgnored private var grabOrder: [Int] = []
    @ObservationIgnored private var untangledTime: Float = 0
    /// The dragon must stay free for a moment, with its body released, before the win is declared.
    @ObservationIgnored private let solveDelay: Float = 0.6
    /// Crossing points, updated every frame (not observed: only RealityKit reads them).
    @ObservationIgnored private(set) var crossingPoints: [SIMD3<Float>] = []
    /// Progress (0...1) of `action`, updated every frame: only RealityKit reads it.
    var actionProgress: Float { behavior.actionProgress }
    /// Game time, for the animations.
    @ObservationIgnored private(set) var time: Float = 0
    /// The flying dragon (around the tree, towards the player, while settling, free), in scene space.
    /// `nil` while it lies in the play area: then the simulation is drawn.
    @ObservationIgnored private var flight: DragonFlight?
    @ObservationIgnored private var freeTime: Float = 0
    /// Seconds of celebration in the play area before taking off.
    @ObservationIgnored private let takeoffDelay: Float = 1.5
    /// After the win: takes off, sweeps once in front of the player, hovers in front of their eyes to thank them
    /// with a roar and flies away (`DragonFlight.Settings.farewell` keeps it all in front of them).
    @ObservationIgnored private let farewell: [DragonFlight.Maneuver] = [.takeoff, .cruise, .hover, .depart]
    /// Just settled, the body blends smoothly from the flight's shape to the simulated one.
    @ObservationIgnored private var settleFrom: [SIMD3<Float>]?
    @ObservationIgnored private var settleTime: Float = 0
    @ObservationIgnored private let settleDuration: Float = 0.5
    /// From the dragon's space (play area) to scene space, updated every frame.
    @ObservationIgnored private var worldFromLocal = matrix_identity_float4x4
    /// Last known position of the player's eyes (scene space).
    @ObservationIgnored private var viewer = SIMD3<Float>(0, 1.15, 0)
    /// Where the player is looking (scene space).
    @ObservationIgnored private var viewerForward = SIMD3<Float>(0, 0, -1)
    /// Strain filtered over time: the dragon's reaction to a pull builds up and fades, it never flickers.
    @ObservationIgnored private var smoothedStrain: Float = 0
    /// How fast `strain` follows the body's tension (1/s).
    @ObservationIgnored private let strainResponsiveness: Float = 6
    /// Space `flight` works in, towards the scene: the tree (the island's anchor) while the dragon is
    /// captive, so it turns and bobs with the island; the identity when it flies in the scene.
    @ObservationIgnored private var worldFromFlight = matrix_identity_float4x4
    /// Angry, it circles the tree faster.
    @ObservationIgnored private let alertedOrbitSpeed: Float = 1.6
    /// How long the dragon stays angry after being tapped, before calming down around the tree again.
    @ObservationIgnored let alertDuration: Float = 3
    @ObservationIgnored private var alertedTime: Float = 0

    init(shape: TangleShape = .trefoil,
         config: TangleConfig = TangleConfig(),
         difficulty: DifficultySettings = DifficultySettings()) {
        self.shape = shape
        simulation = TangleSimulation(config: config, positions: shape.positions(config: config))
        behavior = DragonBehavior(settings: difficulty)
    }

    var config: TangleConfig { simulation.config }
    /// Positions of the simulation (the puzzle), in the dragon's space.
    var nodePositions: [SIMD3<Float>] { simulation.positions }
    /// Positions to draw, in the dragon's space: the simulation or, while flying, the flight.
    var displayPositions: [SIMD3<Float>] {
        guard let flight else {
            guard let settleFrom else { return simulation.positions }
            let amount = settleTime / settleDuration
            let blend = amount * amount * (3 - 2 * amount)
            return zip(settleFrom, simulation.positions).map { simd_mix($0, $1, SIMD3(repeating: blend)) }
        }
        let localFromFlight = worldFromLocal.inverse * worldFromFlight
        return flight.positions.map { Self.transform($0, by: localFromFlight) }
    }
    /// 0...1: fades into the sky as it leaves (and stays invisible until it has a place to be).
    var dragonOpacity: Float {
        if phase == .gone { return 0 }
        guard let flight else { return phase == .captive || phase == .alerted ? 0 : 1 }
        // Fades while moving away, within a couple of metres: before reaching the real room's walls or ceiling.
        let amount = flight.departFade
        return 1 - amount * amount * (3 - 2 * amount)
    }
    var flightManeuver: DragonFlight.Maneuver? { flight?.maneuver }
    var flightProgress: Float { flight?.maneuverProgress ?? 0 }
    /// Velocity of the flying head, in the dragon's space.
    var flightVelocity: SIMD3<Float> {
        guard let flight else { return .zero }
        let direction = worldFromLocal.inverse * worldFromFlight * SIMD4(flight.velocity, 0)
        return SIMD3(direction.x, direction.y, direction.z)
    }
    /// Node dragged by the player (not by the dragon) that the head looks at.
    var lookedAtNodeIndex: Int? { grabOrder.first }

    // MARK: - Dragon actions

    /// The player taps the dragon circling the tree: it gets angry (glares, growls, snorts smoke) for
    /// `alertDuration` seconds, then calms down and keeps circling. Only the artifact (or the debug button in
    /// the dragon panel) brings it down (`callDragon`).
    func tapDragon() {
        guard phase == .captive else { return }
        phase = .alerted
        alertedTime = 0
        refreshMood()
    }

    /// The dragon leaves the tree: flies to the player, stops to look at them, then settles in front of
    /// them, tangling itself up. Called when the artifact reaches it (or by the debug button).
    func callDragon() {
        guard phase == .captive || phase == .alerted, let flight else { return }
        resetPuzzle()
        // From the island's space to the scene's: from now on it flies free of the island.
        flight.transform(by: worldFromFlight)
        worldFromFlight = matrix_identity_float4x4
        flight.landingKnot = simulation.positions.map { Self.transform($0, by: worldFromLocal) }
        flight.perform([.approach, .land], viewer: viewer)
        phase = .approaching
        refreshMood()
    }

    /// Restarts the tangle (same initial knot), staying in the mini-game.
    func restartPuzzle() {
        guard phase == .untangling else { return }
        resetPuzzle()
        refreshCrossings()
        refreshMood()
    }

    /// Restarts the dragon's scene: captive around the tree again (the island stays as it is).
    func restartScene() {
        resetPuzzle()
        phase = .captive
        flight = nil
        worldFromFlight = matrix_identity_float4x4
        isFlying = false
        freeTime = 0
        crossingPoints = []
        if crossingCount != 0 { crossingCount = 0 }
        refreshMood()
    }

    /// Restarts the whole game: dragon scene, island and play area back as at launch.
    func resetGame() {
        restartScene()
        isDragonPanelVisible = false
        islandPlacement = .standard
        placement = .seated
    }

    private func resetPuzzle() {
        simulation = TangleSimulation(config: config, positions: shape.positions(config: config))
        behavior.reset()
        userGrabbedNodes = []
        grabOrder = []
        untangledTime = 0
        restlessness = 0
        settleFrom = nil
        if handGrabs != HandGrabs() { handGrabs.reset() }
        smoothedStrain = 0
        if strain != 0 { strain = 0 }
    }

    /// Can be called several times with different nodes: each hand holds its own node.
    func grab(node index: Int) {
        guard phase == .untangling, !userGrabbedNodes.contains(index) else { return }
        // If the dragon is thrashing, the player wins.
        behavior.interrupt(simulation)
        guard simulation.grab(index) else { return }
        userGrabbedNodes.insert(index)
        grabOrder.append(index)
    }

    /// `point` is in the dragon's local space (the plane it lies on is y = 0, y > 0 is above).
    func drag(node index: Int, to point: SIMD3<Float>) {
        guard userGrabbedNodes.contains(index) else { return }
        simulation.drag(index, to: point)
    }

    func release(node index: Int) {
        guard userGrabbedNodes.remove(index) != nil else { return }
        simulation.release(index)
        grabOrder.removeAll { $0 == index }
    }

    // MARK: - Island actions

    /// The island turns around the trunk; the captive dragon turns with it.
    func rotateIsland(by angle: Float) {
        setIslandYaw(islandPlacement.yaw + angle)
    }

    func setIslandYaw(_ yaw: Float) {
        // Stays between -π and π: the view eases towards the closest angle.
        islandPlacement.yaw = atan2(sin(yaw), cos(yaw))
    }

    func resetIslandRotation() {
        islandPlacement.yaw = IslandPlacement.standard.yaw
    }

    // MARK: - Play area actions

    func rotatePlayArea(yaw: Float) {
        placement.yaw = yaw
    }

    func setTilt(_ tilt: Float) {
        placement.tilt = min(max(tilt, PlayAreaPlacement.tiltRange.lowerBound), PlayAreaPlacement.tiltRange.upperBound)
    }

    func resetPlacement() {
        placement = .seated
    }

    // MARK: - Game loop

    /// Called every frame by the `DragonBodySystem`.
    /// - Parameters:
    ///   - viewer: the player's eyes in scene space (the flying dragon circles them).
    ///   - viewerForward: where the player is looking, in scene space (the free dragon stays in front of them).
    ///   - worldFromLocal: transform from the dragon's space to the scene's.
    ///   - orbit: path around the tree and where the tree is in the scene (nil = no island).
    func update(deltaTime: Float, viewer: SIMD3<Float>, viewerForward: SIMD3<Float> = SIMD3(0, 0, -1),
                worldFromLocal: float4x4, orbit: AnchoredOrbit?) {
        time += deltaTime
        self.worldFromLocal = worldFromLocal
        self.viewer = viewer
        self.viewerForward = viewerForward

        switch phase {
        case .captive, .alerted, .approaching, .landing:
            updateJourney(deltaTime: deltaTime, orbit: orbit)
        case .untangling:
            updatePuzzle(deltaTime: deltaTime)
        case .free, .gone:
            updateFreedom(deltaTime: deltaTime)
        }
    }

    /// From the tree to the play area: the flight follows the script decided when the dragon is called.
    private func updateJourney(deltaTime: Float, orbit: AnchoredOrbit?) {
        let onIsland = phase == .captive || phase == .alerted
        if flight == nil {
            // The dragon is born around the tree as soon as the island is known. It flies in the tree's space,
            // where the body (same length in the scene) measures 1/scale.
            guard let orbit else { return }
            flight = DragonFlight.captive(on: anchorPath(orbit), nodeCount: config.nodeCount,
                                          segmentLength: config.segmentLength / orbit.scale)
        }
        guard let flight else { return }
        if onIsland, let orbit {
            worldFromFlight = orbit.worldFromAnchor
            flight.orbit = anchorPath(orbit)
        }
        let flightFromWorld = worldFromFlight.inverse
        let forward = flightFromWorld * SIMD4(viewerForward, 0)
        flight.update(deltaTime: deltaTime, viewer: Self.transform(viewer, by: flightFromWorld),
                      viewerForward: SIMD3(forward.x, forward.y, forward.z))

        if phase == .alerted {
            alertedTime += deltaTime
            if alertedTime >= alertDuration {
                phase = .captive
                refreshMood()
            }
        }

        if phase == .approaching && flight.maneuver == .land { phase = .landing }
        if flight.isFinished {
            // Settled: from now on the simulation moves it (the tangle is the one it just traced).
            settleFrom = displayPositions
            settleTime = 0
            self.flight = nil
            phase = .untangling
            refreshCrossings()
            refreshMood()
        }
    }

    private func updatePuzzle(deltaTime: Float) {
        if settleFrom != nil {
            settleTime += deltaTime
            if settleTime >= settleDuration { settleFrom = nil }
        }
        behavior.update(deltaTime: deltaTime, crossings: crossingCount,
                        userIsGrabbing: !userGrabbedNodes.isEmpty, simulation: simulation)
        simulation.step(deltaTime: deltaTime)
        refreshCrossings()

        let rawStrain = max(0, min(1, (simulation.tension - 1) / (config.maxTension - 1)))
        smoothedStrain += (rawStrain - smoothedStrain) * (1 - exp(-deltaTime * strainResponsiveness))
        let newStrain = smoothedStrain < 0.01 ? 0 : smoothedStrain
        if abs(newStrain - strain) > 0.05 || (newStrain == 0 && strain != 0) { strain = newStrain }
        if abs(behavior.restlessness - restlessness) > 0.02 || behavior.restlessness == 0 && restlessness != 0 {
            restlessness = behavior.restlessness
        }

        if crossingCount == 0 && !simulation.hasGrabs {
            untangledTime += deltaTime
            if untangledTime >= solveDelay {
                phase = .free
                freeTime = 0
                crossingPoints = []
            }
        } else {
            untangledTime = 0
        }
        refreshMood()
    }

    /// Path in the tree's space; the speed is in m/s in the scene, so it is divided by the scale.
    private func anchorPath(_ orbit: AnchoredOrbit) -> OrbitPath {
        var path = orbit.path
        path.speed = path.speed / orbit.scale * (phase == .alerted ? alertedOrbitSpeed : 1)
        return path
    }

    /// After the win: a short celebration in the play area, then take-off, farewell and departure into the sky.
    private func updateFreedom(deltaTime: Float) {
        freeTime += deltaTime
        if let flight {
            flight.update(deltaTime: deltaTime, viewer: viewer, viewerForward: viewerForward)
            if flight.isFinished && phase != .gone { phase = .gone }
            return
        }
        simulation.step(deltaTime: deltaTime)
        if freeTime >= takeoffDelay {
            let start = simulation.positions.map { Self.transform($0, by: worldFromLocal) }
            flight = DragonFlight(start: start, segmentLength: config.segmentLength, settings: .farewell,
                                  plan: farewell, viewer: viewer, viewerForward: viewerForward)
            isFlying = true
        }
    }

    private static func transform(_ point: SIMD3<Float>, by matrix: float4x4) -> SIMD3<Float> {
        let result = matrix * SIMD4(point, 1)
        return SIMD3(result.x, result.y, result.z)
    }

    private func refreshMood() {
        let newMood: DragonMood = if isSolved {
            .free
        } else if phase == .alerted {
            .restless
        } else if phase != .untangling {
            .calm
        } else if behavior.isWriggling {
            .wriggling
        } else if !userGrabbedNodes.isEmpty {
            .annoyed
        } else if behavior.restlessness > 0 {
            .restless
        } else {
            .calm
        }
        if newMood != mood { mood = newMood }
        if behavior.currentAction != action { action = behavior.currentAction }
    }

    private func refreshCrossings() {
        let crossings = simulation.crossings()
        crossingPoints = crossings.map(\.position)
        // Assign only when it changes, so the views are not invalidated every frame.
        if crossings.count != crossingCount { crossingCount = crossings.count }
    }
}

// MARK: - Hands (manipulation events)

extension UntangleViewModel {
    /// One or two hands started holding a node (each node has its own manipulation: one per hand).
    func manipulationBegan(node index: Int, hands: Set<HandGrabs.Hand>) {
        apply(handGrabs.began(node: index, hands: hands))
    }

    /// The node passed from one hand to the other, or a second hand joined or left.
    func manipulationHandedOff(node index: Int, to hands: Set<HandGrabs.Hand>) {
        apply(handGrabs.handedOff(node: index, to: hands))
    }

    func manipulationReleased(node index: Int) {
        apply(handGrabs.released(node: index))
    }

    func manipulationEnded(node index: Int) {
        apply(handGrabs.ended(node: index))
    }

    private func apply(_ changes: [HandGrabs.Change]) {
        for change in changes {
            switch change {
            case .grab(let index): grab(node: index)
            case .release(let index): release(node: index)
            }
        }
    }
}
