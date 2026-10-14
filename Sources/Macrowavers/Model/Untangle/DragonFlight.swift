import Foundation
import simd

/// Il drago in volo: prigioniero attorno all'albero, in arrivo verso l'utente, mentre si posa sulla
/// piattaforma e, libero, prima di volare via.
/// Lavora nello spazio della scena immersiva (metri, origine ai piedi dell'utente, y in alto).
///
/// Il corpo usa il "follow the leader": la testa vola e lascia una scia, ogni vertebra si trova sulla scia
/// a distanza fissa dalla precedente. Così il corpo serpeggia esattamente lungo la traiettoria della testa,
/// come un drago orientale, senza bisogno di fisica.
final class DragonFlight {
    enum Maneuver: Equatable {
        /// Si stacca dalla piattaforma salendo con battiti forti.
        case takeoff
        /// Plana in cerchio attorno all'utente, salendo e scendendo.
        case cruise
        /// Picchiata: passa di lato all'utente, più in basso, e risale.
        case swoop
        /// Si ferma davanti all'utente, lo guarda e ruggisce con una fiammata verso l'alto.
        case hover
        /// Giro della morte verticale.
        case loop
        /// Prigioniero: gira attorno all'albero dell'isola lungo `OrbitPath`, finché non viene chiamato.
        case orbit
        /// Chiamato: vola verso l'utente e si ferma davanti a lui, guardandolo.
        case approach
        /// Si posa sulla piattaforma: la testa ripercorre il groviglio dalla coda, il corpo la segue
        /// e alla fine giace esattamente nella forma di `landingKnot`.
        case land
        /// Se ne va: sale e si allontana nel cielo, sempre più veloce.
        case depart

        var duration: Float {
            switch self {
            case .takeoff: 2.2
            case .cruise: 6
            case .swoop: 3
            case .hover: 3.2
            case .loop: 3
            case .orbit: .infinity
            case .approach: 5
            // Dipende dalla lunghezza del percorso: vedi `landingProgress`.
            case .land: .infinity
            case .depart: 6
            }
        }

        /// Alla fine il volo si ferma (il drago è a terra o è sparito) invece di scegliere un'altra manovra.
        var isFinal: Bool { self == .land || self == .depart }

        /// Manovre "nella stanza": rispettano quota e distanza massima dall'utente.
        var staysInRoom: Bool {
            switch self {
            case .takeoff, .cruise, .swoop, .hover, .loop: true
            case .orbit, .approach, .land, .depart: false
            }
        }
    }

    struct Settings {
        var speed: Float = 0.75
        /// Quanto velocemente la testa cambia direzione (più alto = virate più strette).
        var steering: Float = 2.2
        /// Distanza orizzontale dall'utente entro cui vola.
        var orbitRadius: ClosedRange<Float> = 1.1...2.0
        /// Altezze di volo (m dal pavimento).
        var altitude: ClosedRange<Float> = 0.9...2.1
        /// Il drago non si avvicina mai più di così alla testa dell'utente (comfort).
        var personalSpace: Float = 0.7
        /// A che distanza dagli occhi dell'utente si ferma quando arriva (oltre lo spazio personale).
        var approachDistance: Float = 1.0
        /// Velocità della testa mentre traccia il groviglio posandosi.
        var landingSpeed: Float = 0.65
    }

    let settings: Settings
    private(set) var segmentLength: Float
    private(set) var positions: [SIMD3<Float>]
    private(set) var velocity: SIMD3<Float>
    private(set) var maneuver = Maneuver.takeoff
    private(set) var maneuverProgress: Float = 0
    /// Ha finito l'ultima manovra (`Maneuver.isFinal`): il corpo resta fermo.
    private(set) var isFinished = false
    /// Percorso attorno all'albero, aggiornato ogni frame (l'isola fluttua).
    var orbit: OrbitPath?
    /// Dove si poserà (indice 0 = testa), nello spazio della scena: da impostare prima di `.land`.
    var landingKnot: [SIMD3<Float>] = []

    /// Scia della testa: dal punto più vecchio (indice 0) alla testa attuale (ultimo).
    private var trail: [SIMD3<Float>]
    private var elapsed: Float = 0
    private var orbitDirection: Float = 1
    private var orbitAngle: Float = 0
    private var maneuverOrigin = SIMD3<Float>.zero
    private var maneuverForward = SIMD3<Float>(0, 0, -1)
    private var random = SystemRandomNumberGenerator()
    /// Manovre già decise (copione): finite queste, il drago sceglie da solo.
    private var plan: [Maneuver] = []
    /// Angolo della testa su `orbit`.
    private var pathAngle: Float = 0
    private var approachSpot = SIMD3<Float>.zero
    private var departDirection = SIMD3<Float>(0, 0, -1)
    /// Percorso della testa mentre si posa e quanto ne ha già fatto.
    private var landingPath: [SIMD3<Float>] = []
    private var landingLength: Float = 0
    private var landingTraveled: Float = 0
    private var landingSegment = 0
    private var landingSegmentStart: Float = 0

    /// `start`: posizioni attuali del corpo (indice 0 = testa) nello spazio della scena.
    /// `plan`: manovre da eseguire in ordine (la prima parte subito).
    init(start: [SIMD3<Float>], segmentLength: Float, settings: Settings = Settings(),
         plan: [Maneuver] = [.takeoff], orbit: OrbitPath? = nil) {
        self.settings = settings
        self.segmentLength = segmentLength
        self.orbit = orbit
        positions = start
        // La scia iniziale è il corpo stesso, dalla coda alla testa: al decollo il corpo si "srotola".
        trail = start.reversed()
        let forward = simd_normalize(start[0] - start[1])
        velocity = SIMD3(forward.x, 0.6, forward.z) * 0.3
        orbitDirection = Bool.random(using: &random) ? 1 : -1
        perform(plan.isEmpty ? [.takeoff] : plan, viewer: start[0])
    }

    /// Prigioniero dell'isola: il corpo è già avvolto all'albero lungo il percorso.
    static func captive(on orbit: OrbitPath, nodeCount: Int, segmentLength: Float,
                        settings: Settings = Settings()) -> DragonFlight {
        let start = orbit.body(headAngle: 0, count: nodeCount, segmentLength: segmentLength)
        let flight = DragonFlight(start: start, segmentLength: segmentLength, settings: settings, plan: [.orbit], orbit: orbit)
        // Scia fitta lungo la curva (non le corde tra i nodi): il corpo non scatta al primo frame.
        let bodyAngle = segmentLength * Float(nodeCount + 4) / max(orbit.radius - orbit.radialSwing, 0.05)
        flight.trail = stride(from: -bodyAngle, to: 0, by: 0.01).map(orbit.point(at:)) + [start[0]]
        return flight
    }

    /// Porta il volo in un altro spazio (es. dall'isola alla scena quando il drago la lascia).
    /// `matrix` deve avere scala uniforme: le distanze, compresa quella tra le vertebre, si scalano con lei.
    func transform(by matrix: float4x4) {
        let column = matrix.columns.0
        let scale = simd_length(SIMD3(column.x, column.y, column.z))
        let point = { (value: SIMD3<Float>) -> SIMD3<Float> in
            let result = matrix * SIMD4(value, 1)
            return SIMD3(result.x, result.y, result.z)
        }
        positions = positions.map(point)
        trail = trail.map(point)
        let direction = matrix * SIMD4(velocity, 0)
        velocity = SIMD3(direction.x, direction.y, direction.z)
        segmentLength *= scale
        orbit = nil
    }

    /// Sostituisce il copione: la prima manovra parte subito, dalla posizione e velocità attuali.
    func perform(_ maneuvers: [Maneuver], viewer: SIMD3<Float>) {
        guard let first = maneuvers.first else { return }
        plan = Array(maneuvers.dropFirst())
        isFinished = false
        begin(first, viewer: viewer)
    }

    func update(deltaTime: Float, viewer: SIMD3<Float>) {
        guard !isFinished else { return }
        let dt = min(deltaTime, 1.0 / 30.0)
        guard dt > 0 else { return }
        elapsed += dt
        maneuverProgress = maneuver == .land ? landingProgress : min(elapsed / maneuver.duration, 1)
        if maneuverProgress >= 1 {
            if maneuver.isFinal && plan.isEmpty {
                isFinished = true
                return
            }
            begin(plan.isEmpty ? nextManeuver() : plan.removeFirst(), viewer: viewer)
        }

        let head: SIMD3<Float>
        switch maneuver {
        case .orbit:
            // Percorso fisso: la velocità è quella che ne risulta (serve al rig e alla manovra successiva).
            head = advanceOnOrbit(dt: dt)
            velocity = (head - positions[0]) / dt
        case .land:
            head = advanceOnLandingPath(dt: dt)
            velocity = (head - positions[0]) / dt
        default:
            steer(toward: target(viewer: viewer), viewer: viewer, dt: dt)
            head = positions[0] + velocity * dt
        }

        if simd_distance(head, trail.last!) > segmentLength * 0.1 { trail.append(head) }
        positions = bodyAlongTrail(head: head)
        trimTrail()
    }

    // MARK: - Manovre

    private func begin(_ next: Maneuver, viewer: SIMD3<Float>) {
        maneuver = next
        elapsed = 0
        maneuverProgress = 0
        maneuverOrigin = positions[0]
        var forward = velocity
        forward.y = 0
        maneuverForward = simd_length(forward) > 1e-4 ? simd_normalize(forward) : SIMD3(0, 0, -1)
        let offset = positions[0] - viewer
        orbitAngle = atan2(offset.z, offset.x)
        if next == .cruise && Float.random(in: 0...1, using: &random) < 0.3 { orbitDirection *= -1 }

        switch next {
        case .orbit:
            if let orbit { pathAngle = orbit.angle(closestTo: positions[0]) }
        case .approach:
            // Davanti all'utente, sulla linea tra lui e il drago (cioè dove sta guardando quando lo tocca).
            let toDragon = SIMD3(offset.x, 0, offset.z)
            let direction = simd_length(toDragon) > 1e-4 ? simd_normalize(toDragon) : SIMD3(0, 0, -1)
            approachSpot = viewer + direction * settings.approachDistance
            approachSpot.y = viewer.y - 0.05
        case .land:
            beginLanding()
        case .depart:
            // Via dall'utente, oltre il punto in cui si trova.
            departDirection = simd_length(SIMD3(offset.x, 0, offset.z)) > 1e-4
                ? simd_normalize(SIMD3(offset.x, 0, offset.z)) : SIMD3(0, 0, -1)
        default:
            break
        }
    }

    /// "Vita propria": sceglie la prossima manovra a caso, con pesi, senza ripetere picchiate o ruggiti di fila.
    private func nextManeuver() -> Maneuver {
        let options: [(Maneuver, Float)] = switch maneuver {
        case .takeoff: [(.cruise, 1)]
        case .cruise: [(.swoop, 0.35), (.hover, 0.3), (.loop, 0.2), (.cruise, 0.15)]
        case .swoop, .hover, .loop, .approach, .land, .depart: [(.cruise, 1)]
        case .orbit: [(.orbit, 1)]
        }
        var roll = Float.random(in: 0..<options.reduce(0) { $0 + $1.1 }, using: &random)
        for (option, weight) in options {
            roll -= weight
            if roll < 0 { return option }
        }
        return .cruise
    }

    /// Punto verso cui vola la testa, secondo la manovra.
    private func target(viewer: SIMD3<Float>) -> SIMD3<Float> {
        let progress = maneuverProgress
        let midRadius = (settings.orbitRadius.lowerBound + settings.orbitRadius.upperBound) / 2
        let midAltitude = (settings.altitude.lowerBound + settings.altitude.upperBound) / 2

        switch maneuver {
        case .takeoff:
            // Sale quasi in verticale, poi si allontana un po'.
            return maneuverOrigin + SIMD3(0, 0.9, 0) + maneuverForward * (0.6 * progress)
        case .cruise:
            // Cerchio attorno all'utente, raggio e quota che respirano.
            orbitAngle += orbitDirection * 0.012
            let radius = midRadius + 0.3 * sin(elapsed * 0.7)
            let height = midAltitude + 0.45 * sin(elapsed * 0.9)
            return SIMD3(viewer.x + radius * cos(orbitAngle + orbitDirection * 0.6), height,
                         viewer.z + radius * sin(orbitAngle + orbitDirection * 0.6))
        case .swoop:
            // Prima scende di lato all'utente, poi risale dall'altra parte.
            let toViewer = SIMD3(viewer.x - maneuverOrigin.x, 0, viewer.z - maneuverOrigin.z)
            let across = simd_length(toViewer) > 1e-4 ? simd_normalize(toViewer) : maneuverForward
            let side = SIMD3(-across.z, 0, across.x) * orbitDirection
            let low = SIMD3(viewer.x, settings.altitude.lowerBound, viewer.z) + side * (settings.personalSpace + 0.5)
            let far = low + across * 1.4 + SIMD3(0, 0.8, 0)
            return progress < 0.5 ? low : far
        case .hover:
            // Davanti all'utente, all'altezza dei suoi occhi, con un leggero ondeggiare.
            let toDragon = SIMD3(maneuverOrigin.x - viewer.x, 0, maneuverOrigin.z - viewer.z)
            let direction = simd_length(toDragon) > 1e-4 ? simd_normalize(toDragon) : SIMD3(0, 0, -1)
            let spot = viewer + direction * (settings.personalSpace + 0.6)
            return SIMD3(spot.x, viewer.y, spot.z) + SIMD3(0.15 * sin(elapsed * 2), 0.1 * sin(elapsed * 3), 0)
        case .loop:
            // Cerchio verticale nel piano (avanti, su).
            let angle = progress * 2 * .pi
            let radius: Float = 0.45
            let center = maneuverOrigin + maneuverForward * 0.6 + SIMD3(0, radius, 0)
            return center + maneuverForward * (radius * sin(angle) + 0.5) - SIMD3(0, radius * cos(angle), 0)
        case .approach:
            // Arriva e resta sospeso con un leggero ondeggiare.
            return approachSpot + SIMD3(0.06 * sin(elapsed * 1.7), 0.04 * sin(elapsed * 2.3), 0)
        case .depart:
            // Bersaglio che scappa avanti e in alto: traiettoria che sale verso il cielo.
            return positions[0] + (departDirection + SIMD3(0, 0.5, 0)) * 2
        case .orbit, .land:
            // Seguono un percorso, non sterzano.
            return positions[0]
        }
    }

    private func steer(toward target: SIMD3<Float>, viewer: SIMD3<Float>, dt: Float) {
        let head = positions[0]
        var desired = target - head
        let distance = simd_length(desired)
        let speed: Float = switch maneuver {
        // In sospensione rallenta fino quasi a fermarsi.
        case .hover, .approach: min(settings.speed, distance * 1.5) + 0.08
        // Andandosene accelera.
        case .depart: settings.speed * (1 + 2.5 * maneuverProgress)
        default: settings.speed
        }
        desired = distance > 1e-4 ? desired / distance * speed : .zero

        // Spazio personale: spinta via dalla testa dell'utente.
        let fromViewer = head - viewer
        let viewerDistance = simd_length(fromViewer)
        if viewerDistance < settings.personalSpace + 0.2, viewerDistance > 1e-4 {
            desired += fromViewer / viewerDistance * settings.speed * 2
        }
        if maneuver.staysInRoom {
            // Resta tra pavimento e soffitto.
            if head.y < settings.altitude.lowerBound - 0.1 { desired.y += settings.speed }
            if head.y > settings.altitude.upperBound + 0.2 { desired.y -= settings.speed }
            // Non si allontana troppo (pareti della stanza).
            let horizontal = SIMD3(fromViewer.x, 0, fromViewer.z)
            if simd_length(horizontal) > settings.orbitRadius.upperBound + 0.4 {
                desired -= simd_normalize(horizontal) * settings.speed
            }
        }

        velocity += (desired - velocity) * min(1, dt * settings.steering)
    }
}

// MARK: - Percorsi (albero, atterraggio)

extension DragonFlight {
    private func advanceOnOrbit(dt: Float) -> SIMD3<Float> {
        guard let orbit else { return positions[0] }
        pathAngle += orbit.speed / orbit.radius * dt
        // La curva si chiude ogni due giri: l'angolo resta piccolo (precisione dei Float).
        if pathAngle > 4 * .pi { pathAngle -= 4 * .pi }
        return orbit.point(at: pathAngle)
    }

    /// Curva morbida dalla testa (nella direzione in cui vola) alla punta della coda del groviglio,
    /// arrivando già orientata lungo il groviglio; poi il groviglio stesso, dalla coda alla testa.
    private func beginLanding() {
        landingPath = []
        landingTraveled = 0
        landingSegment = 0
        landingSegmentStart = 0
        guard landingKnot.count > 1 else {
            landingLength = 0
            return
        }
        let start = positions[0]
        let tail = landingKnot[landingKnot.count - 1]
        let along = simd_normalize(landingKnot[landingKnot.count - 2] - tail)
        let speed = simd_length(velocity)
        let forward = speed > 1e-4 ? velocity / speed : along
        let handle = max(0.15, simd_distance(start, tail) * 0.4)
        let control1 = start + forward * handle
        let control2 = tail - along * handle
        let samples = 24
        for step in 0...samples {
            // Bézier cubica.
            let along = Float(step) / Float(samples)
            let rest = 1 - along
            landingPath.append(rest * rest * rest * start + 3 * rest * rest * along * control1
                               + 3 * rest * along * along * control2 + along * along * along * tail)
        }
        landingPath += landingKnot.reversed().dropFirst()
        landingLength = zip(landingPath, landingPath.dropFirst()).reduce(0) { $0 + simd_distance($1.0, $1.1) }
    }

    private var landingProgress: Float {
        landingLength > 0 ? min(landingTraveled / landingLength, 1) : 1
    }

    private func advanceOnLandingPath(dt: Float) -> SIMD3<Float> {
        guard landingPath.count > 1 else { return positions[0] }
        landingTraveled = min(landingTraveled + settings.landingSpeed * dt, landingLength)
        // Avanza segmento per segmento (il cursore non torna mai indietro).
        while landingSegment < landingPath.count - 2 {
            let length = simd_distance(landingPath[landingSegment], landingPath[landingSegment + 1])
            if landingSegmentStart + length >= landingTraveled { break }
            landingSegmentStart += length
            landingSegment += 1
        }
        let from = landingPath[landingSegment]
        let to = landingPath[landingSegment + 1]
        let length = simd_distance(from, to)
        let fraction = length > 1e-6 ? min((landingTraveled - landingSegmentStart) / length, 1) : 1
        return simd_mix(from, to, SIMD3(repeating: fraction))
    }
}

extension DragonFlight {
    // MARK: - Corpo lungo la scia

    private func bodyAlongTrail(head: SIMD3<Float>) -> [SIMD3<Float>] {
        var result = [head]
        result.reserveCapacity(positions.count)
        var index = trail.count - 1
        var cursor = head
        var needed = segmentLength
        while result.count < positions.count {
            guard index > 0 else {
                // Scia finita: prolunga nella direzione dell'ultimo tratto.
                let last = result.count > 1 ? result[result.count - 1] - result[result.count - 2] : SIMD3(0, 0, segmentLength)
                result.append(result[result.count - 1] + simd_normalize(last) * segmentLength)
                continue
            }
            let previous = trail[index - 1]
            let step = simd_distance(cursor, previous)
            if step >= needed {
                cursor += (previous - cursor) * (needed / step)
                result.append(cursor)
                needed = segmentLength
            } else {
                needed -= step
                cursor = previous
                index -= 1
            }
        }
        return result
    }

    /// Tiene solo la scia che serve al corpo (più un margine).
    private func trimTrail() {
        let bodyLength = segmentLength * Float(positions.count + 4)
        var length: Float = 0
        var index = trail.count - 1
        while index > 0 && length < bodyLength {
            length += simd_distance(trail[index], trail[index - 1])
            index -= 1
        }
        if index > 0 { trail.removeFirst(index) }
    }
}
