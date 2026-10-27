import Observation
import Portfolio
import RPC

/// One window's view of its network's portfolios: the account that the window observes, read from the shared store.
///
/// Create a new coordinator when changing networks. The store keeps each wallet's state, which windows that show the
/// same wallet share; the service continues to own caching, pricing, subscriptions, and token lists.
@MainActor
@Observable
final class PortfolioCoordinator: PortfolioCoordinating {
    /// The observed wallet's latest state, or `nil` before any data is available or without an account.
    var update: Update? { portfolio?.update }

    /// The observed wallet's latest holdings in display order, or none without a snapshot or an account.
    var holdings: [Holding] { portfolio?.holdings ?? [] }

    /// Why the observed wallet's latest update failed, or `nil` when it didn't.
    var error: PortfolioError? { portfolio?.error }

    /// The account that the window shows, whose wallet the window reads.
    private var account: Account?
    private let store: PortfolioStore
    private let network: Network

    /// Creates a window's view of a network's portfolios.
    /// - Parameters:
    ///   - store: The portfolios that every window shares.
    ///   - network: The network that the window shows.
    init(store: PortfolioStore, network: Network) {
        self.store = store
        self.network = network
    }

    /// The shown account's shared portfolio, once a window observes it.
    private var portfolio: WalletPortfolio? {
        account.flatMap { store.portfolio(for: $0, on: network) }
    }

    /// Shows an account's wallet, and observes it until the view task is cancelled while the scene is active.
    /// - Parameters:
    ///   - account: The selected account, or `nil` to clear selection.
    ///   - isActive: Whether the presenting scene is active.
    func observe(for account: Account?, isActive: Bool) async {
        guard !Task.isCancelled else { return }
        if self.account != account { self.account = account }
        guard isActive, let account else { return }
        await store.observe(account, on: network)
    }

    /// Forces one reload for the observed wallet; the service also reconnects a disconnected subscription.
    func refresh() async {
        guard let account else { return }
        await store.refresh(account, on: network)
    }
}
