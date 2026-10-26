import SwiftUI
import UIKit

/// The app icon picker under Start (`AppIconChoice`): the system changes the icon and tells the player. Hidden where
/// the system does not support alternate icons.
struct AppIconMenu: View {
    @State private var selection = AppIconChoice(alternateIconName: UIApplication.shared.alternateIconName)

    var body: some View {
        if UIApplication.shared.supportsAlternateIcons {
            Menu {
                Picker("App Icon", selection: $selection) {
                    ForEach(AppIconChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
            } label: {
                Label("App Icon", systemImage: "app.badge")
            }
            .accessibilityHint("Chooses the icon of the app on the Home View")
            .onChange(of: selection) { previous, choice in
                Task { await apply(choice, otherwise: previous) }
            }
        }
    }

    /// Asks the system for the icon; if it refuses, the menu shows the icon it kept.
    private func apply(_ choice: AppIconChoice, otherwise previous: AppIconChoice) async {
        guard UIApplication.shared.alternateIconName != choice.alternateIconName else { return }
        do {
            try await UIApplication.shared.setAlternateIconName(choice.alternateIconName)
        } catch {
            print("⚠️ App icon not changed to \(choice.rawValue): \(error)")
            selection = previous
        }
    }
}
