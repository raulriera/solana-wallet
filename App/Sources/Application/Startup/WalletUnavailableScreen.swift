import SwiftUI

/// Shows that the saved wallets couldn't load, with a button that tries again.
struct WalletUnavailableScreen: View {
    let retry: () -> Void

    var body: some View {
        UnavailableScreen(title: "Wallets Unavailable",
                          message: "Your saved wallets could not be loaded. Please try again.",
                          systemImage: "exclamationmark.triangle") {
            Button("Try Again", action: retry)
                .buttonStyle(.primary)
        }
    }
}
