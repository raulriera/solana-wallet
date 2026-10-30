import RPC
import SwiftUI

/// Presents the add-token screen in its own navigation stack.
struct TokenAdditionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let addition: TokenAdditionModel
    let account: Account
    let network: Network

    var body: some View {
        NavigationStack {
            TokenAdditionScreen(addition: addition)
                .tokenAdditionLifecycle(for: account, on: network)
                .onChange(of: addition.isAdded) { dismiss() }
                .cancellationAction()
        }
        .limitedTextSize()
    }
}
