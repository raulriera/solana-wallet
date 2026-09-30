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
                                  palette: palette, select: selectAppTheme, remove: settings.remove)
            if let wallet {
                WalletThemeSection(wallet: wallet, themeName: walletThemeName, palette: palette)
            }
            ThemePacksSection(settings: settings, palette: palette)
            if let activity = settings.activity {
                AppearanceActivitySection(activity: activity, palette: palette)
            }
        }
        .navigationTitle("Appearance")
        .navigationDestination(for: AppearancePreferences.Scope.self) { scope in
            ThemeChooser(entries: settings.entries, scope: scope, selection: selection(for: scope),
                         isBusy: settings.activity != nil, palette: palette) { id in
                settings.select(id, for: scope)
            }
        }
        .foregroundStyle(palette.primaryText, palette.secondaryText)
        .tint(palette.accent)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .disabled(settings.activity != nil || settings.appearance.snapshot == nil)
    }

    /// Saves an inline choice using the canonical Original application preference.
    /// - Parameter id: The chosen built-in or imported theme identity.
    private func selectAppTheme(_ id: UUID) {
        settings.select(id == OriginalAppearance.id ? nil : id, for: .application)
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
