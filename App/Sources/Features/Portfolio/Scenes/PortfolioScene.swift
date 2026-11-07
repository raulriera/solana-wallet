import RPC
import SwiftUI

/// Shows the Portfolio tab for an account on a network.
struct PortfolioScene: View {
    @State private var removal = TokenRemovalModel()
    @State private var privateBalance = PrivateBalanceModel()
    let account: Account
    let network: Network
    let connection: any ProviderConnecting<RPCConnectionError>

    var body: some View {
        PortfolioSplitView(account: account, network: network, connection: connection, removal: removal,
                           privateBalance: privateBalance)
            .tokenRemovalLifecycle()
    }
}
