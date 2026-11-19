import RPC
import SwiftUI

/// Observes a wallet's portfolio while the scene is in the foreground and the provider settings are read, and
/// refreshes it after each transaction settles.
private struct PortfolioObservation: ViewModifier {
    @Environment(PortfolioStore.self) private var portfolios
    @Environment(TransactionStore.self) private var transactions
    let account: Account
    let network: Network

    func body(content: Content) -> some View {
        let settledCount = transactions.settledCount(for: TransactionRecord.Key(account: account.id, network: network))
        content
            .observation(of: account, on: network, in: PortfolioStore.self)
            .task(id: settledCount) {
                guard settledCount > 0 else { return }
                await portfolios.refresh(account, on: network)
            }
    }
}

extension View {
    /// Observes a wallet's portfolio while the scene is in the foreground and the provider settings are read, and
    /// refreshes it after each transaction settles.
    ///
    /// - Parameters:
    ///   - account: The account to observe.
    ///   - network: The network to observe the account on.
    /// - Returns: A view that observes the wallet.
    func portfolioObservation(of account: Account, on network: Network) -> some View {
        modifier(PortfolioObservation(account: account, network: network))
    }
}
