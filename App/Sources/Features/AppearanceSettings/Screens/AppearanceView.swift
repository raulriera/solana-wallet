import SwiftUI

/// Shows the appearance settings: the app theme and theme packs.
struct AppearanceView: View {
    @Environment(\.palette) private var palette
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
            .listRowBackground(palette.surface)

            ThemeSelectionSection(entries: settings.entries,
                                  selection: settings.appearance.snapshot?.preferences.themeID ?? OriginalAppearance.id,
                                  actions: settings)
            ThemePacksSection(settings: settings)
        }
        .animation(.default, value: settings.entryIDs)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(palette.primaryText, palette.secondaryText)
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .background(palette.background)
        .disabled(settings.appearance.snapshot == nil)
    }
}
