import RPC
import SwiftUI
import Transactions

/// Observes the window's wallet while its scene is active, whichever section is visible, and reads its balances again
/// after each of its transactions on the window's network settles.
private struct PortfolioObservation: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(TransactionStore.self) private var transactions
    @Environment(ProviderStore.self) private var providers
    let account: Account
    let network: Network
    let coordinator: any PortfolioCoordinating

    /// Runs observation for the lifetime of the content's task.
    /// - Parameter content: The window's sections; a task inside one section would stop on every section switch.
    /// - Returns: Content that observes the wallet until the scene leaves or the wallet changes.
    func body(content: Content) -> some View {
        let session = Session(accountID: account.id, coordinator: ObjectIdentifier(coordinator),
                              isActive: scenePhase == .active && providers.isRead)
        let settledCount = transactions.settledCount(for: TransactionRecord.Key(account: account.id, network: network))
        content
            .task(id: session) { await coordinator.observe(for: account.address.value, isActive: session.isActive) }
            // A settled transaction changed the balances, failed or not, since it paid its fee, even when its review
            // closed before it landed.
            .task(id: settledCount) {
                guard settledCount > 0 else { return }
                await coordinator.refresh()
            }
    }

    /// The observation's identity: a new wallet, a replaced coordinator, or scene activity restarts it. It runs only
    /// while the provider settings are read, so a reset stops it.
    ///
    /// A new provider doesn't restart it: the shared portfolios observe every observed wallet again themselves. The
    /// coordinator itself, not the window's stored network, keys the task, so observation always runs on the
    /// coordinator that the window shows.
    private struct Session: Equatable {
        let accountID: UUID
        let coordinator: ObjectIdentifier
        let isActive: Bool
    }
}

extension View {
    /// Observes a wallet's portfolio for as long as this view's scene is active, and reads its balances again after each
    /// of its transactions settles.
    /// - Parameters:
    ///   - account: The window's wallet.
    ///   - network: The window's network, whose settled transactions read the balances again.
    ///   - coordinator: The window's portfolio presentation; a replacement, as for another network, restarts
    ///     observation.
    /// - Returns: A view whose task observes the wallet, independent of the visible section.
    func portfolioObservation(of account: Account, on network: Network,
                              coordinator: any PortfolioCoordinating) -> some View {
        modifier(PortfolioObservation(account: account, network: network, coordinator: coordinator))
    }
}
