import RPC
import SwiftUI

/// Observes the window's wallet while its scene is active, whichever section is visible, and reads its balances again
/// after each of its transactions on the window's network settles.
///
/// Tabs such as Portfolio and Contacts read the wallet from the shared portfolios, so the window observes it rather
/// than any one tab.
private struct PortfolioObservation: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PortfolioStore.self) private var portfolios
    @Environment(TransactionStore.self) private var transactions
    @Environment(ProviderStore.self) private var providers
    let account: Account
    let network: Network

    /// Runs observation for the lifetime of the content's task.
    /// - Parameter content: The window's sections; a task inside one section would stop on every section switch.
    /// - Returns: Content that observes the wallet until the scene leaves or the wallet changes.
    func body(content: Content) -> some View {
        let session = Session(accountID: account.id, network: network,
                              isActive: scenePhase == .active && providers.isRead)
        let settledCount = transactions.settledCount(for: TransactionRecord.Key(account: account.id, network: network))
        content
            .task(id: session) {
                guard session.isActive else { return }
                await portfolios.observe(account, on: network)
            }
            // A settled transaction changed the balances, failed or not, since it paid its fee, even when its review
            // closed before it landed.
            .task(id: settledCount) {
                guard settledCount > 0 else { return }
                await portfolios.refresh(account, on: network)
            }
    }

    /// The observation's identity: another account, another network, or scene activity restarts it. It runs only
    /// while the provider settings are read, so a reset stops it.
    ///
    /// A new provider doesn't restart it: the shared portfolios observe every observed wallet again themselves.
    private struct Session: Equatable {
        let accountID: UUID
        let network: Network
        let isActive: Bool
    }
}

extension View {
    /// Observes a wallet's portfolio for as long as this view's scene is active, and reads its balances again after each
    /// of its transactions settles.
    ///
    /// The portfolio is the environment's ``PortfolioStore``, which every tab reads.
    /// - Parameters:
    ///   - account: The window's account.
    ///   - network: The window's network, whose portfolio is observed and whose settled transactions read the balances
    ///     again.
    /// - Returns: A view whose task observes the wallet, independent of the visible section.
    func portfolioObservation(of account: Account, on network: Network) -> some View {
        modifier(PortfolioObservation(account: account, network: network))
    }
}
