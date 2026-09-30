import SwiftUI

/// Navigation rows for the shared default and the current wallet's override.
struct ThemeSelectionSection: View {
    let appThemeName: String
    let wallet: AppearanceWallet?
    let walletThemeName: String
    let palette: RenderedPalette

    var body: some View {
        Section {
            NavigationLink(value: AppearancePreferences.Scope.application) {
                LabeledContent("App Theme", value: appThemeName)
            }
            if let wallet {
                NavigationLink(value: AppearancePreferences.Scope.wallet(wallet.id)) {
                    LabeledContent("Wallet Theme", value: walletThemeName)
                }
            }
        } footer: {
            if let wallet { Text("Wallet Theme applies to \(wallet.name) in every window.") }
        }
        .listRowBackground(palette.surface)
        .listRowSeparatorTint(palette.separator)
    }
}
