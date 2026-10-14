import Foundation

/// Capitoli della storia del drago: dall'isola volante, al groviglio, alla libertà.
enum DragonPhase: Equatable {
    /// Prigioniero dell'isola: gira attorno all'albero e aspetta che l'utente lo tocchi.
    case captive
    /// Toccato: vola verso l'utente e si ferma davanti a lui (in futuro lo calmerà l'artefatto).
    case approaching
    /// Si posa sulla piattaforma tracciando il groviglio con il proprio corpo.
    case landing
    /// Il minigioco: l'utente lo sgroviglia.
    case untangling
    /// Sgrovigliato: festeggia, ringrazia l'utente e vola via nel cielo.
    case free
    /// Volato via: la storia è finita.
    case gone

    enum Interaction {
        /// Il corpo non risponde (il drago è in volo).
        case none
        /// Toccare il drago lo chiama verso l'utente.
        case tap
        /// Ogni parte del corpo si afferra e si trascina (una per mano).
        case grab
    }

    var interaction: Interaction {
        switch self {
        case .captive: .tap
        case .untangling: .grab
        case .approaching, .landing, .free, .gone: .none
        }
    }
}
