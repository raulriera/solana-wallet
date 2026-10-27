import Foundation
import Observation
import Portfolio
import RPC
import Transactions

/// One window's view of its network's portfolios: the wallet that the window observes, read from the shared store.
///
/// Create a new coordinator when changing networks. The store keeps each wallet's state, which windows that show the
/// same wallet share; the service continues to own caching, pricing, subscriptions, and token lists.
@MainActor
@Observable
final class PortfolioCoordinator: PortfolioCoordinating {
    /// The observed wallet's latest state, or `nil` before any data is available or without a wallet.
    var update: Update? { owner.flatMap { store.update(for: $0, on: network) } }

    /// The observed wallet's latest holdings in display order, or none without a snapshot or a wallet.
    var holdings: [Holding] { owner.map { store.holdings(for: $0, on: network) } ?? [] }

    /// The latest update's error, classified without retaining the provider's error.
    var error: PortfolioError? { update?.error.map(PortfolioError.init) }

    /// The wallet that the window shows, whose state the window reads.
    private var owner: String?
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

    /// Shows a wallet, and observes it until the view task is cancelled while the scene is active.
    /// - Parameters:
    ///   - owner: The selected public wallet address, or `nil` to clear selection.
    ///   - isActive: Whether the presenting scene is active.
    func observe(for owner: String?, isActive: Bool) async {
        guard !Task.isCancelled else { return }
        if self.owner != owner { self.owner = owner }
        guard isActive, let owner else { return }
        await store.observe(owner, on: network)
    }

    /// Forces one reload for the observed wallet; the service also reconnects a disconnected subscription.
    func refresh() async {
        guard let owner else { return }
        await store.refresh(owner, on: network)
    }

    /// Looks up a pasted mint address on the window's network.
    /// - Parameter mint: The pasted mint address.
    /// - Returns: The token with its on-chain name and symbol, and its logo when the provider has one.
    /// - Throws: `TokenLookupError` when the address isn't a fungible token mint, or a request error.
    func token(at mint: Address) async throws -> TokenPreview {
        try await store.token(at: mint, on: network)
    }

    /// Adds a token to the selected wallet's list; an observed wallet then reads its balances again.
    /// - Parameter token: A token that ``token(at:)`` found.
    /// - Throws: `TokenListError` for a full or unreadable list, or a file-system error if the list can't be saved.
    func add(_ token: ListedToken) async throws {
        guard let owner else { return }
        try await store.add(token, for: owner, on: network)
    }

    /// Removes a token from the selected wallet's list; the service sends the next snapshot without it.
    /// - Parameter mint: The mint address of a listed token.
    /// - Throws: `TokenListError.unreadable` for an unreadable list, or a file-system error if the list can't be saved.
    func remove(_ mint: Address) async throws {
        guard let owner else { return }
        try await store.remove(mint, for: owner, on: network)
    }
}
