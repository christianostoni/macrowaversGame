import Foundation
import Testing
@testable import Macrowavers

struct AppIconTests {
    @Test func stoneDragonIsThePrimaryIcon() {
        #expect(AppIconChoice.stoneDragon.alternateIconName == nil)
        #expect(AppIconChoice(alternateIconName: nil) == .stoneDragon)
        // A name the app does not know (an icon removed in an update) falls back on the primary one.
        #expect(AppIconChoice(alternateIconName: "AppIconGone") == .stoneDragon)
    }

    @Test(arguments: AppIconChoice.allCases)
    func everyChoiceIsFoundAgainFromTheSystemsName(choice: AppIconChoice) {
        #expect(AppIconChoice(alternateIconName: choice.alternateIconName) == choice)
    }

    /// The build lists every alternate icon in the app's Info.plist: one missing from
    /// `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` would only show up as an error when the player picks it.
    @Test func everyAlternateIconIsInTheBundle() {
        let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any]
        let alternates = icons?["CFBundleAlternateIcons"] as? [String: Any] ?? [:]
        for name in AppIconChoice.allCases.compactMap(\.alternateIconName) {
            #expect(alternates[name] != nil, "\(name) is not an alternate icon of the app")
        }
    }
}
