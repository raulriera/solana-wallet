import SwiftUI

/// The buttons that create or import a wallet.
struct WelcomeActions: View {
    let createWallet: () -> Void
    let importWallet: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button("Create Wallet", action: createWallet)
                .buttonStyle(.primary)

            Button("Import Wallet", action: importWallet)
                .buttonStyle(.secondary)
        }
    }
}
