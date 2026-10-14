import Foundation
import simd

/// Posizione dell'isola volante nello spazio immersivo (origine ai piedi dell'utente, -Z davanti).
/// L'origine dell'asset è la base del tronco, sul terreno: `position` è il punto in cui sta l'albero.
struct IslandPlacement: Equatable {
    var position: SIMD3<Float>
    /// Rotazione attorno all'asse verticale (radianti).
    var yaw: Float
    /// L'asset è in metri "veri" (isola larga ~2,5 m, albero alto ~1,4 m): ridotto per la stanza.
    var scale: Float

    /// Oltre la piattaforma, con il tronco all'altezza degli occhi di chi è seduto: il drago che gli gira
    /// attorno si vede bene e la roccia sotto resta sollevata da terra (~17 cm).
    static let standard = IslandPlacement(position: SIMD3(0, 1.0, -2.2), yaw: 0, scale: 0.6)

    var rotation: simd_quatf {
        simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
    }
}

/// Percorso del drago prigioniero attorno all'albero: una curva torica di due giri avvolta al tronco.
/// Dopo un giro raggio e altezza si invertono, quindi il corpo (più lungo di un giro) si attorciglia
/// all'albero senza mai attraversare se stesso. La testa percorre la curva, il corpo la segue
/// ("follow the leader" in `DragonFlight`).
struct OrbitPath: Equatable {
    /// Base del tronco.
    var center = SIMD3<Float>.zero
    /// Raggio medio attorno al tronco.
    var radius: Float = 0.6
    /// Di quanto il raggio cresce e cala tra i due giri.
    var radialSwing: Float = 0.12
    /// Altezza media sopra il terreno: tra i cespugli e la chioma.
    var height: Float = 0.32
    /// Di quanto sale e scende tra i due giri.
    var verticalSwing: Float = 0.13
    /// Velocità della testa (m/s nello spazio della scena: non dipende dalla scala).
    var speed: Float = 0.35

    /// Valori dell'asset dell'isola (base del tronco = origine, metri dell'asset).
    static let aroundTree = OrbitPath()

    /// Stesso percorso in un altro spazio: centro spostato, misure scalate (la velocità no).
    func placed(at center: SIMD3<Float>, scale: Float) -> OrbitPath {
        var path = self
        path.center = center
        path.radius *= scale
        path.radialSwing *= scale
        path.height *= scale
        path.verticalSwing *= scale
        return path
    }

    /// Punto del percorso. La curva si chiude ogni due giri (4π).
    func point(at angle: Float) -> SIMD3<Float> {
        let half = angle / 2
        let distance = radius + radialSwing * cos(half)
        return center + SIMD3(distance * cos(angle), height + verticalSwing * sin(half), distance * sin(angle))
    }

    /// Angolo del percorso più vicino a `point` (sceglie tra i due giri).
    func angle(closestTo point: SIMD3<Float>) -> Float {
        let offset = point - center
        let base = atan2(offset.z, offset.x)
        let other = base + 2 * .pi
        return simd_distance(self.point(at: base), point) <= simd_distance(self.point(at: other), point) ? base : other
    }

    /// Corpo disteso lungo il percorso dietro alla testa (indice 0 = testa), nodi a `segmentLength`.
    func body(headAngle: Float, count: Int, segmentLength: Float) -> [SIMD3<Float>] {
        var result = [point(at: headAngle)]
        var angle = headAngle
        var previous = result[0]
        var walked: Float = 0
        let step: Float = 0.002
        while result.count < count {
            angle -= step
            let next = point(at: angle)
            let length = simd_distance(previous, next)
            if walked + length >= segmentLength {
                // Punto esatto a `segmentLength` lungo la curva: niente errore che si accumula verso la coda.
                let fraction = (segmentLength - walked) / max(length, 1e-6)
                let node = simd_mix(previous, next, SIMD3(repeating: fraction))
                result.append(node)
                previous = node
                walked = 0
                angle += step
            } else {
                walked += length
                previous = next
            }
        }
        return result
    }
}
