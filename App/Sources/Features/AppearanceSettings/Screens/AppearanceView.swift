import SwiftUI

/// Shows the appearance settings: the app theme, the token layout, and theme packs.
struct AppearanceView: View {
    @Bindable var settings: AppearanceSettingsModel

    var body: some View {
        Form {
            Section {
                TitleCardContent(
                    title: "Appearance",
                    message: "Choose the app's theme and how the Portfolio shows tokens, and import your own theme packs.",
                    systemImage: "paintpalette.fill"
                )
            }

            ThemeSelectionSection(entries: settings.entries,
                                  selection: settings.appearance.preferences.themeID ?? OriginalAppearance.id,
                                  actions: settings)
            TokenLayoutSection(selection: $settings.tokenLayout)
            ThemePacksSection(settings: settings)
        }
        .formStyle(.choices)
        .animation(.default, value: settings.entryIDs)
        .navigationTitle("Appearance")
        .toolbarTitleDisplayMode(.inline)
        .disabled(settings.appearance.snapshot == nil)
    }
}
