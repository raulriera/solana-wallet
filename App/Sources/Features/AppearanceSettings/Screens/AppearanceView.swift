import SwiftUI

/// Shows the appearance settings: the app theme, the wallet theme, and theme packs.
struct AppearanceView: View {
    @Environment(\.palette) private var palette
    let settings: AppearanceSettingsModel
    let wallet: AppearanceWallet?

    private var walletThemeName: String? {
        let snapshot = settings.appearance.snapshot
        return wallet.flatMap { snapshot?.preferences.walletThemeIDs[$0.id] }
            .flatMap { snapshot?.entries[$0]?.name }
    }

    var body: some View {
        Form {
            Section {
                TitleCardContent(
                    title: "Appearance",
                    message: "Choose themes for the app and your wallets, and import your own theme packs.",
                    systemImage: "paintpalette.fill"
                )
            }
            .listRowBackground(palette.surface)

            ThemeSelectionSection(entries: settings.entries,
                                  selection: settings.appearance.snapshot?.preferences.appThemeID ?? OriginalAppearance.id,
                                  actions: settings)
            if let wallet {
                WalletThemeSection(wallet: wallet, themeName: walletThemeName)
            }
            ThemePacksSection(settings: settings)
        }
        .animation(.default, value: settings.entryIDs)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: AppearancePreferences.Scope.self) { scope in
            ThemeChooser(entries: settings.entries, entryIDs: settings.entryIDs, scope: scope, selection: selection(for: scope),
                         actions: settings)
        }
        .foregroundStyle(palette.primaryText, palette.secondaryText)
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .background(palette.background)
        .disabled(settings.appearance.snapshot == nil)
    }

    /// Returns the theme selected for the app or a wallet, without the app's theme as a fallback.
    ///
    /// - Parameter scope: The app or wallet.
    /// - Returns: The selected theme, or `nil` for none.
    private func selection(for scope: AppearancePreferences.Scope) -> UUID? {
        switch scope {
        case .application: settings.appearance.snapshot?.preferences.appThemeID
        case .wallet(let id): settings.appearance.snapshot?.preferences.walletThemeIDs[id]
        }
    }
}
