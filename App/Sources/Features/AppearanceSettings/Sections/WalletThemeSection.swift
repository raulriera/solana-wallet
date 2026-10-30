import SwiftUI

/// A section that opens a wallet's theme choices.
struct WalletThemeSection: View {
    @Environment(\.palette) private var palette
    let wallet: AppearanceWallet
    /// The wallet's theme name, or `nil` when it uses the app default.
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
