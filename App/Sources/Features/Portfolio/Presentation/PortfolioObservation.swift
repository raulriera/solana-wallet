import RPC
import SwiftUI

/// Observes a wallet's portfolio while the scene is active and refreshes it after each transaction settles.
private struct PortfolioObservation: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PortfolioStore.self) private var portfolios
    @Environment(TransactionStore.self) private var transactions
    @Environment(ProviderStore.self) private var providers
    let account: Account
    let network: Network

    func body(content: Content) -> some View {
        let session = Session(accountID: account.id, network: network,
                              isActive: scenePhase == .active && providers.isRead)
        let settledCount = transactions.settledCount(for: TransactionRecord.Key(account: account.id, network: network))
        content
            .task(id: session) {
                guard session.isActive else { return }
                await portfolios.observe(account, on: network)
            }
            .task(id: settledCount) {
                guard settledCount > 0 else { return }
                await portfolios.refresh(account, on: network)
            }
    }

    /// The identity of a running observation.
    private struct Session: Equatable {
        let accountID: UUID
        let network: Network
        let isActive: Bool
    }
}

extension View {
    /// Observes a wallet's portfolio while the scene is active and refreshes it after each transaction settles.
    ///
    /// - Parameters:
    ///   - account: The account to observe.
    ///   - network: The network to observe.
    /// - Returns: A view that observes the wallet.
    func portfolioObservation(of account: Account, on network: Network) -> some View {
        modifier(PortfolioObservation(account: account, network: network))
    }
}
