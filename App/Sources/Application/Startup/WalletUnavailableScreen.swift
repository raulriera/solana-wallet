import SwiftUI

/// Offers an explicit retry while leaving unreadable wallet storage untouched.
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

#Preview {
    WalletUnavailableScreen(retry: {})
}
