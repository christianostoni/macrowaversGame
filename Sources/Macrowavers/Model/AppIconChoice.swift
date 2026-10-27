import Foundation

/// The app icons the player can pick on the Start window: the icon sets of the asset catalog. `AppIcon` is the
/// primary one; the others are alternates, listed in the build setting `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`.
/// Sources: `Assets/Icon/<rawValue>.icon`.
enum AppIconChoice: String, CaseIterable, Identifiable {
    /// The design team's stone dragon: the default.
    case stoneDragon = "AppIcon"
    /// The red dragon coiled around an orange.
    case redDragon = "AppIconRedDragon"
    /// The first icon: the black dragon coiled around an orange.
    case blackDragon = "AppIconBlackDragon"

    var id: Self { self }

    /// What `setAlternateIconName` takes: nil for the primary icon.
    var alternateIconName: String? {
        self == .stoneDragon ? nil : rawValue
    }

    var title: String {
        switch self {
        case .stoneDragon: "Stone Dragon"
        case .redDragon: "Red Dragon"
        case .blackDragon: "Black Dragon"
        }
    }

    /// The icon the system shows, from its alternate icon name (nil, or a name not listed here: the primary one).
    init(alternateIconName: String?) {
        self = Self.allCases.first { $0.alternateIconName == alternateIconName } ?? .stoneDragon
    }
}
