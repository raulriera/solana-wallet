import SwiftUI

/// Opens the current wallet's explicit override or application inheritance choice.
struct WalletThemeSection: View {
    let wallet: AppearanceWallet
    let themeName: String
    let palette: RenderedPalette

    var body: some View {
        Section {
            NavigationLink(value: AppearancePreferences.Scope.wallet(wallet.id)) {
                LabeledContent("Wallet Theme", value: themeName)
            }
        } footer: {
            Text("Wallet Theme applies to \(wallet.name) in every window.")
        }
        .listRowBackground(palette.surface)
        .listRowSeparatorTint(palette.separator)
    }
}
