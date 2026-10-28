import RPC
import SwiftUI

/// Owns a window's Portfolio tab for an account on a network: its token removals, which outlive a removed token's
/// details, and its private-balance workflows, which SOL's details run.
///
/// The tab keeps its workflows while the person switches tabs; the window gives it a new identity for another account
/// or network, which starts it again on the token list with no attempt or move left from the previous one.
struct PortfolioScene: View {
    @State private var removal = TokenRemovalModel()
    @State private var privateBalance = PrivateBalanceModel()
    /// The account whose portfolio shows.
    let account: Account
    /// The network whose portfolio shows.
    let network: Network
    let connection: any ProviderConnecting<ProviderConnectionError>

    var body: some View {
        PortfolioSplitView(account: account, network: network, connection: connection, removal: removal,
                           privateBalance: privateBalance)
            .tokenRemovalLifecycle()
    }
}
