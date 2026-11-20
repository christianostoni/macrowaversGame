import SwiftUI

/// The Settings window, opened by the Settings button under Start: pushed in place of the launch window, which comes
/// back when it closes (Done or the window's close button), so Start is never hidden behind it. The player's settings
/// (`GameSettings`), the app icon (`AppIconMenu`) and, in About, the game's pages on its website: the privacy policy
/// (Apple asks for a link inside the app as well as on the App Store), support, and the credits, which name the
/// artists whose CC BY work the game uses (`CREDITS.md`). The pages open in Safari.
struct SettingsView: View {
    static let windowID = "SettingsWindow"

    private static let privacy = URL(string: "https://macrowavers.pages.dev/privacy/")!
    private static let support = URL(string: "https://macrowavers.pages.dev/support/")!
    private static let credits = URL(string: "https://macrowavers.pages.dev/credits/")!
    private static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"

    @Environment(GameSettings.self) private var settings
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Toggle("Music", isOn: $settings.isMusicOn)
                    Toggle("Narrator's Voice", isOn: $settings.isNarratorVoiceOn)
                } header: {
                    Text("Sound")
                } footer: {
                    Text("The story's subtitles show even without the narrator's voice.")
                }
                Section {
                    Toggle("Play with Taps", isOn: $settings.playsWithTaps)
                } header: {
                    Text("Gestures")
                } footer: {
                    Text("""
                        A tap chops the pineapple and brews the elixir, and the dragon flies itself on the ride. \
                        The game won't ask to track your hands.
                        """)
                }
                Section {
                    AppIconMenu()
                }
                Section {
                    LabeledContent("Version", value: Self.version)
                    WebsiteLink("Privacy Policy", systemImage: "hand.raised", destination: Self.privacy)
                    WebsiteLink("Support", systemImage: "questionmark.circle", destination: Self.support)
                    WebsiteLink("Credits", systemImage: "person.2", destination: Self.credits)
                } header: {
                    Text("About")
                } footer: {
                    Text("Made by Macrowavers, a team of student developers and designers, after a Persian fairy tale.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismissWindow(id: Self.windowID) }
                }
            }
        }
        .frame(width: 540, height: 700)
    }
}

/// An About row that opens a page of the website: in the rows' own colour, not a link's tint, and the arrow at its end
/// says it leaves the game for Safari.
private struct WebsiteLink: View {
    let title: LocalizedStringKey
    let systemImage: String
    let destination: URL

    init(_ title: LocalizedStringKey, systemImage: String, destination: URL) {
        self.title = title
        self.systemImage = systemImage
        self.destination = destination
    }

    @Environment(\.openURL) private var openURL

    var body: some View {
        // A button that opens the page, not a `Link`: in a list, a link is drawn in the link colour whatever its
        // label asks for.
        Button {
            openURL(destination)
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
        }
        .accessibilityAddTraits(.isLink)
        .accessibilityHint("Opens in Safari")
    }
}

#Preview {
    SettingsView()
        .environment(GameSettings())
}
