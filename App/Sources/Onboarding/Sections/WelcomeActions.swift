import SwiftUI

/// Groups the setup choices for either layout supplied by the screen.
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
