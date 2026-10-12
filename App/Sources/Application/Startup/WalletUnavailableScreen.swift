import SwiftUI

/// Offers an explicit retry while leaving unreadable wallet storage untouched.
struct WalletUnavailableScreen: View {
    @Environment(\.palette) private var palette
    @State private var contentInset = LayoutMetrics.contentMargin
    let retry: () -> Void

    var body: some View {
        ScrollView {
            ContentUnavailableView("Wallets Unavailable", systemImage: "exclamationmark.triangle",
                description: Text("Your saved wallets could not be loaded. Please try again."))
                .foregroundStyle(palette.primaryText)
        }
        .defaultScrollAnchor(.center, for: .alignment)
        .readableContentMargins(inset: $contentInset, addsSafeArea: false)
        .pinnedAction(inset: contentInset) {
            Button("Try Again", action: retry)
                .buttonStyle(.primary)
        }
        .background(palette.background)
    }
}

#Preview {
    WalletUnavailableScreen(retry: {})
}
