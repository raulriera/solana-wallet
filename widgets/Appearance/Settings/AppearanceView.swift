import SwiftUI

/// Composes appearance settings from independently updating sections.
struct AppearanceView: View {
    let settings: AppearanceSettings
    let wallet: AppearanceWallet?
    let palette: RenderedPalette

    private var walletThemeName: String {
        let snapshot = settings.appearance.snapshot
        return wallet.flatMap { snapshot?.preferences.walletThemeIDs[$0.id] }
            .flatMap { snapshot?.entries[$0]?.name } ?? "Use App Default"
    }

    var body: some View {
        Form {
            ThemeSelectionSection(entries: settings.entries,
                                  selection: settings.appearance.snapshot?.preferences.appThemeID ?? OriginalAppearance.id,
                                  palette: palette, actions: settings)
            if let wallet {
                WalletThemeSection(wallet: wallet, themeName: walletThemeName, palette: palette)
            }
            ThemePacksSection(settings: settings, palette: palette)
        }
        .animation(.default, value: settings.entries.map(\.id))
        .navigationTitle("Appearance")
        .navigationDestination(for: AppearancePreferences.Scope.self) { scope in
            ThemeChooser(entries: settings.entries, scope: scope, selection: selection(for: scope),
                         palette: palette, actions: settings)
        }
        .foregroundStyle(palette.primaryText, palette.secondaryText)
        .tint(palette.accent)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .disabled(settings.appearance.snapshot == nil)
    }

    /// Reads the explicit selection for a chooser without resolving wallet inheritance.
    /// - Parameter scope: The preference being edited.
    /// - Returns: The persisted identity, or `nil` for Original or wallet inheritance.
    private func selection(for scope: AppearancePreferences.Scope) -> UUID? {
        switch scope {
        case .application: settings.appearance.snapshot?.preferences.appThemeID
        case .wallet(let id): settings.appearance.snapshot?.preferences.walletThemeIDs[id]
        }
    }
}
