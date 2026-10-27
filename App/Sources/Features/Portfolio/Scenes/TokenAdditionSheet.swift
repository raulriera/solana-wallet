import RPC
import SwiftUI

/// Presents adding a token in its own navigation container, so the system places the sheet on each display.
///
/// The sheet closes itself on Cancel and once the token is added.
struct TokenAdditionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let addition: TokenAdditionModel
    /// The account whose list the token joins.
    let account: Account
    /// The network whose list the token joins.
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
