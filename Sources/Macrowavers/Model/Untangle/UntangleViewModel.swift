import Foundation
import Observation
import simd

/// ViewModel della storia del drago: prigioniero sull'isola, chiamato dall'utente, sgrovigliato, libero.
/// Espone alle View lo stato da mostrare e le azioni dell'utente; non conosce RealityKit né SwiftUI.
@MainActor
@Observable
final class UntangleViewModel {
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    // MARK: - Stato per le View

    var immersiveSpaceState = ImmersiveSpaceState.closed
    /// Capitolo della storia in corso.
    private(set) var phase = DragonPhase.captive
    private(set) var crossingCount = 0
    var isSolved: Bool { phase == .free || phase == .gone }
    private(set) var mood = DragonMood.calm
    /// 0...1: il drago sta per dimenarsi.
    private(set) var restlessness: Float = 0
    /// 0...1: quanto è teso il corpo mentre l'utente tira.
    private(set) var strain: Float = 0
    private(set) var placement = PlayAreaPlacement.seated
    /// Movimento in corso durante un attacco d'ira (nil = nessuno).
    private(set) var action: DragonAction?
    /// Sgrovigliato, il drago ha preso il volo.
    private(set) var isFlying = false
    let islandPlacement = IslandPlacement.standard

    // MARK: - Model

    @ObservationIgnored private(set) var simulation: TangleSimulation
    @ObservationIgnored let shape: TangleShape
    @ObservationIgnored private let behavior: DragonBehavior
    /// Nodi tenuti dall'utente (uno per mano).
    @ObservationIgnored private(set) var userGrabbedNodes: Set<Int> = []
    /// Ordine di presa: la testa guarda il primo nodo afferrato.
    @ObservationIgnored private var grabOrder: [Int] = []
    @ObservationIgnored private var untangledTime: Float = 0
    /// Il drago deve restare libero per un attimo, a corpo rilasciato, prima di dichiarare la vittoria.
    @ObservationIgnored private let solveDelay: Float = 0.6
    /// Punti degli incroci, aggiornati ogni frame (non osservati: li legge solo RealityKit).
    @ObservationIgnored private(set) var crossingPoints: [SIMD3<Float>] = []
    /// Avanzamento (0...1) di `action`, aggiornato ogni frame: lo legge solo RealityKit.
    var actionProgress: Float { behavior.actionProgress }
    /// Tempo di gioco, per le animazioni.
    @ObservationIgnored private(set) var time: Float = 0
    /// Il drago in volo (attorno all'albero, verso l'utente, mentre si posa, libero), nello spazio della scena.
    /// `nil` mentre giace sulla piattaforma: allora si disegna la simulazione.
    @ObservationIgnored private var flight: DragonFlight?
    @ObservationIgnored private var freeTime: Float = 0
    /// Secondi di festa sulla piattaforma prima di decollare.
    @ObservationIgnored private let takeoffDelay: Float = 1.5
    /// Dopo la vittoria: decolla, fa un giro attorno all'utente, lo ringrazia con un ruggito e vola via.
    @ObservationIgnored private let farewell: [DragonFlight.Maneuver] = [.takeoff, .cruise, .hover, .depart]
    /// Appena posato, il corpo passa dalla forma del volo a quella simulata in modo morbido.
    @ObservationIgnored private var settleFrom: [SIMD3<Float>]?
    @ObservationIgnored private var settleTime: Float = 0
    @ObservationIgnored private let settleDuration: Float = 0.5
    /// Da spazio del drago (piattaforma) a spazio della scena, aggiornata ogni frame.
    @ObservationIgnored private var worldFromLocal = matrix_identity_float4x4
    /// Ultima posizione nota degli occhi dell'utente (spazio della scena).
    @ObservationIgnored private var viewer = SIMD3<Float>(0, 1.15, 0)

    init(shape: TangleShape = .trefoil,
         config: TangleConfig = TangleConfig(),
         difficulty: DifficultySettings = DifficultySettings()) {
        self.shape = shape
        simulation = TangleSimulation(config: config, positions: shape.positions(config: config))
        behavior = DragonBehavior(settings: difficulty)
    }

    var config: TangleConfig { simulation.config }
    /// Posizioni della simulazione (il puzzle), nello spazio del drago.
    var nodePositions: [SIMD3<Float>] { simulation.positions }
    /// Posizioni da disegnare, nello spazio del drago: la simulazione o, in volo, il volo.
    var displayPositions: [SIMD3<Float>] {
        guard let flight else {
            guard let settleFrom else { return simulation.positions }
            let amount = settleTime / settleDuration
            let blend = amount * amount * (3 - 2 * amount)
            return zip(settleFrom, simulation.positions).map { simd_mix($0, $1, SIMD3(repeating: blend)) }
        }
        let localFromWorld = worldFromLocal.inverse
        return flight.positions.map { Self.transform($0, by: localFromWorld) }
    }
    /// 0...1: si dissolve nel cielo andandosene (e resta invisibile finché non ha un posto dove stare).
    var dragonOpacity: Float {
        if phase == .gone { return 0 }
        guard let flight else { return phase == .captive ? 0 : 1 }
        guard flight.maneuver == .depart else { return 1 }
        // Svanisce mentre si allontana, prima di arrivare al soffitto della stanza reale.
        let amount = max(0, min(1, (flight.maneuverProgress - 0.3) / 0.55))
        return 1 - amount * amount * (3 - 2 * amount)
    }
    var flightManeuver: DragonFlight.Maneuver? { flight?.maneuver }
    var flightProgress: Float { flight?.maneuverProgress ?? 0 }
    /// Velocità della testa in volo, nello spazio del drago.
    var flightVelocity: SIMD3<Float> {
        guard let flight else { return .zero }
        let localFromWorld = worldFromLocal.inverse
        let direction = localFromWorld * SIMD4(flight.velocity, 0)
        return SIMD3(direction.x, direction.y, direction.z)
    }
    /// Nodo trascinato dall'utente (non dal drago) che la testa guarda.
    var lookedAtNodeIndex: Int? { grabOrder.first }

    // MARK: - Azioni sul drago

    /// L'utente tocca il drago che gira attorno all'albero: il drago vola verso di lui, si ferma a guardarlo
    /// e poi si posa sulla piattaforma, aggrovigliandosi. (Simula l'artefatto che lo calmerà.)
    func tapDragon() {
        guard phase == .captive, let flight else { return }
        resetPuzzle()
        flight.landingKnot = simulation.positions.map { Self.transform($0, by: worldFromLocal) }
        flight.perform([.approach, .land], viewer: viewer)
        phase = .approaching
        refreshMood()
    }

    /// Ricomincia il groviglio (stesso nodo iniziale), restando nel minigioco.
    func restartPuzzle() {
        guard phase == .untangling else { return }
        resetPuzzle()
        refreshCrossings()
        refreshMood()
    }

    /// Ricomincia la storia: il drago torna prigioniero attorno all'albero.
    func playAgain() {
        resetPuzzle()
        phase = .captive
        flight = nil
        isFlying = false
        freeTime = 0
        crossingPoints = []
        if crossingCount != 0 { crossingCount = 0 }
        refreshMood()
    }

    private func resetPuzzle() {
        simulation = TangleSimulation(config: config, positions: shape.positions(config: config))
        behavior.reset()
        userGrabbedNodes = []
        grabOrder = []
        untangledTime = 0
        restlessness = 0
        settleFrom = nil
    }

    /// Si può chiamare più volte con nodi diversi: ogni mano tiene il proprio nodo.
    func grab(node index: Int) {
        guard phase == .untangling, !userGrabbedNodes.contains(index) else { return }
        // Se il drago si sta dimenando, l'utente ha la precedenza.
        behavior.interrupt(simulation)
        guard simulation.grab(index) else { return }
        userGrabbedNodes.insert(index)
        grabOrder.append(index)
    }

    /// `point` è nello spazio locale del drago (il piano su cui giace è y = 0, y > 0 è sopra).
    func drag(node index: Int, to point: SIMD3<Float>) {
        guard userGrabbedNodes.contains(index) else { return }
        simulation.drag(index, to: point)
    }

    func release(node index: Int) {
        guard userGrabbedNodes.remove(index) != nil else { return }
        simulation.release(index)
        grabOrder.removeAll { $0 == index }
    }

    // MARK: - Azioni sulla piattaforma

    func movePlayArea(to position: SIMD3<Float>) {
        var position = position
        position.y = min(max(position.y, PlayAreaPlacement.heightRange.lowerBound), PlayAreaPlacement.heightRange.upperBound)
        placement.position = position
    }

    func rotatePlayArea(yaw: Float) {
        placement.yaw = yaw
    }

    func setTilt(_ tilt: Float) {
        placement.tilt = min(max(tilt, PlayAreaPlacement.tiltRange.lowerBound), PlayAreaPlacement.tiltRange.upperBound)
    }

    func resetPlacement() {
        placement = .seated
    }

    // MARK: - Ciclo di gioco

    /// Chiamato ogni frame dal `DragonBodySystem`.
    /// - Parameters:
    ///   - viewer: occhi dell'utente nello spazio della scena (il drago in volo gli gira attorno).
    ///   - worldFromLocal: trasformazione dallo spazio del drago a quello della scena.
    ///   - orbit: percorso attorno all'albero dell'isola, nello spazio della scena (nil = isola assente).
    func update(deltaTime: Float, viewer: SIMD3<Float>, worldFromLocal: float4x4, orbit: OrbitPath?) {
        time += deltaTime
        self.worldFromLocal = worldFromLocal
        self.viewer = viewer

        switch phase {
        case .captive, .approaching, .landing:
            updateJourney(deltaTime: deltaTime, orbit: orbit)
        case .untangling:
            updatePuzzle(deltaTime: deltaTime)
        case .free, .gone:
            updateFreedom(deltaTime: deltaTime)
        }
    }

    /// Dall'albero alla piattaforma: il volo segue il copione deciso al tocco (`tapDragon`).
    private func updateJourney(deltaTime: Float, orbit: OrbitPath?) {
        if flight == nil {
            // Il drago nasce attorno all'albero, appena si sa dov'è l'isola.
            guard let orbit else { return }
            flight = DragonFlight.captive(on: orbit, nodeCount: config.nodeCount, segmentLength: config.segmentLength)
        }
        guard let flight else { return }
        if let orbit { flight.orbit = orbit }
        flight.update(deltaTime: deltaTime, viewer: viewer)

        if phase == .approaching && flight.maneuver == .land { phase = .landing }
        if flight.isFinished {
            // Posato: da qui in poi lo muove la simulazione (il groviglio è quello appena tracciato).
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

        let newStrain = max(0, min(1, (simulation.tension - 1) / (config.maxTension - 1)))
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

    /// Dopo la vittoria: breve festa sulla piattaforma, poi decollo, saluto e partenza nel cielo.
    private func updateFreedom(deltaTime: Float) {
        freeTime += deltaTime
        if let flight {
            flight.update(deltaTime: deltaTime, viewer: viewer)
            if flight.isFinished && phase != .gone { phase = .gone }
            return
        }
        simulation.step(deltaTime: deltaTime)
        if freeTime >= takeoffDelay {
            let start = simulation.positions.map { Self.transform($0, by: worldFromLocal) }
            flight = DragonFlight(start: start, segmentLength: config.segmentLength, plan: farewell)
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
        // Assegna solo se cambia, per non invalidare le View a ogni frame.
        if crossings.count != crossingCount { crossingCount = crossings.count }
    }
}
