import SwiftUI

/// Shows the appearance settings: the app theme and theme packs.
struct AppearanceView: View {
    let settings: AppearanceSettingsModel

    var body: some View {
        Form {
            Section {
                TitleCardContent(
                    title: "Appearance",
                    message: "Choose the app's theme and import your own theme packs.",
                    systemImage: "paintpalette.fill"
                )
            }

            ThemeSelectionSection(entries: settings.entries,
                                  selection: settings.appearance.snapshot?.preferences.themeID ?? OriginalAppearance.id,
                                  actions: settings)
            ThemePacksSection(settings: settings)
        }
        .formStyle(.choices)
        .animation(.default, value: settings.entryIDs)
        .navigationTitle("Appearance")
        .toolbarTitleDisplayMode(.inline)
        .disabled(settings.appearance.snapshot == nil)
    }
}
