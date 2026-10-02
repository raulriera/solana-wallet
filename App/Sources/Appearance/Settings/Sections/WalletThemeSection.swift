import SwiftUI

/// Opens the current wallet's explicit override or application inheritance choice.
struct WalletThemeSection: View {
    @Environment(\.palette) private var palette
    let wallet: AppearanceWallet
    /// The explicit theme's unchanged name, or `nil` when following the app default.
    let themeName: String?

    var body: some View {
        Section {
            NavigationLink(value: AppearancePreferences.Scope.wallet(wallet.id)) {
                LabeledContent("Wallet Theme") {
                    if let themeName {
                        Text(themeName)
                    } else {
                        Text("Use App Default")
                    }
                }
            }
        } footer: {
            Text("Wallet Theme applies to \(wallet.name) in every window.")
        }
        .listRowBackground(palette.surface)
        .listRowSeparatorTint(palette.separator)
    }
}
