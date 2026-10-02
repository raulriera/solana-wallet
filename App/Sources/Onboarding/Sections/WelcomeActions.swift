import SwiftUI

/// Groups the setup choices for either layout supplied by the screen.
struct WelcomeActions: View {
    @Environment(\.palette) private var palette
    let createWallet: () -> Void
    let importWallet: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: createWallet) {
                Text("Create Wallet")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(palette.background)

            Button(action: importWallet) {
                Text("Import Wallet")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
        .tint(palette.primaryText)
    }
}
