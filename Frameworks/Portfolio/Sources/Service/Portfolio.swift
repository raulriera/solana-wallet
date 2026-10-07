import Foundation
public import RPC
public import Transactions

/// A portfolio service that delivers persisted holdings and refreshes stale or explicitly reloaded data.
public struct Portfolio: PortfolioProviding, TokenListProviding {
    private let coordinator: RefreshCoordinator
    private let observer: ObservationCoordinator
    private let tokenLists: TokenListCoordinator

    /// Creates a portfolio service that caches holdings in the app's cache directory
    /// and saves token lists in its Application Support directory.
    ///
    /// - Parameters:
    ///   - rpc: The RPC client that reads balances; every provider supports the request it uses.
    ///   - prices: A same-network price provider; `nil` leaves holdings unpriced and disables price-only refreshes.
    ///   - changes: A same-network subscription provider; `nil` uses the RPC client's capability when available.
    public init(rpc: any RPC, prices: (any PriceProviding)? = nil, changes: (any AccountChangeProviding)? = nil) {
        self.init(rpc: rpc, store: FileSnapshotStore(directory: .cachesDirectory.appendingPathComponent("Portfolio")),
                  prices: prices, changes: changes)
    }

    /// Creates a service with injected stores.
    ///
    /// - Parameters:
    ///   - rpc: The RPC client that reads balances.
    ///   - store: The persistent snapshot store.
    ///   - tokenLists: The token-list store; the default saves lists in Application Support.
    ///   - prices: An optional same-network price provider.
    ///   - now: The current time used to evaluate cache age and record price refreshes.
    ///   - changes: The optional confirmed-change provider, defaulting to the RPC client's capability.
    ///   - pause: Cancellable scheduling for coalescing nearby changes.
    init(rpc: any RPC, store: any SnapshotStoring,
         tokenLists: any TokenListStoring = FileTokenListStore(
            directory: .applicationSupportDirectory.appending(path: "Portfolio/TokenLists", directoryHint: .isDirectory)),
         prices: (any PriceProviding)? = nil,
         now: @escaping @Sendable () -> Date = { Date() }, changes: (any AccountChangeProviding)? = nil,
         pause: @escaping ObservationCoordinator.Pause = { try await Task.sleep(for: $0) }) {
        let lists = TokenListCoordinator(store: tokenLists, network: rpc.network)
        self.tokenLists = lists
        coordinator = RefreshCoordinator(source: BalanceReader(rpc: rpc, tokenLists: lists), store: store,
                                         prices: prices, now: now)
        observer = ObservationCoordinator(refresh: coordinator, changes: changes ?? (rpc as? any AccountChangeProviding),
                                          network: rpc.network, pause: pause)
    }

    /// Returns cached state, refreshing holdings and independent prices according to the policy.
    ///
    /// The service owns cache lookup, persistence, and failure fallback.
    /// Each caller receives its own stream while concurrent callers share the refresh.
    /// Registration completes before this method returns; the refresh arrives through the stream.
    ///
    /// - Parameters:
    ///   - owner: The wallet address whose holdings to retrieve.
    ///   - policy: Whether to reuse fresh data or reload when opening the view or refreshing explicitly.
    /// - Returns: A finite stream of complete states. Cancelling its consuming task
    ///   detaches that consumer without clearing cached data.
    public func updates(for owner: String, policy: RefreshPolicy) async -> AsyncStream<Update> {
        await coordinator.updates(for: owner, policy: policy)
    }

    /// Refreshes only valuations for existing holdings, retaining balances and their retrieval time.
    /// - Parameters:
    ///   - owner: The wallet whose cached holdings to revalue.
    ///   - policy: Whether to reuse recent prices or request new quotes regardless of age.
    /// - Returns: Cached state followed by refreshed prices or an error, without scheduling another cycle.
    public func priceUpdates(for owner: String, policy: RefreshPolicy) async -> AsyncStream<Update> {
        await coordinator.updates(for: owner, scope: .prices, policy: policy)
    }

    /// Observes confirmed wallet changes and reads balances again after each one.
    /// - Parameter owner: The visible wallet to observe until its consuming task is cancelled.
    /// - Returns: Cached state, an initial reload, and event-driven refresh results; disconnects end with an error.
    public func observations(for owner: String) async -> AsyncStream<Update> {
        await observer.observations(for: owner)
    }

    /// Removes the wallet's cached holdings and token list, and stops its active refresh.
    ///
    /// - Parameter owner: The wallet whose local data to remove.
    /// - Throws: A file-system error if the persisted snapshot or token list can't be removed.
    public func removeData(for owner: String) async throws {
        await observer.stop(for: owner)
        try await coordinator.removeData(for: owner)
        try await tokenLists.removeList(for: owner)
    }

    /// Returns an account's saved token list, or the network's defaults when the account has none yet.
    ///
    /// - Parameter owner: The account's wallet address.
    /// - Returns: The account's token list.
    /// - Throws: ``TokenListError/unreadable`` if a saved list exists but can't be read.
    public func tokenList(for owner: String) async throws -> TokenList {
        try await tokenLists.list(for: owner)
    }

    /// Adds a token to an account's list and saves the list.
    ///
    /// - Parameters:
    ///   - token: The token to add; a token that's already listed changes nothing.
    ///   - owner: The account's wallet address.
    /// - Returns: The saved list.
    /// - Throws: ``TokenListError`` for a full or unreadable list, or a file-system error if saving fails.
    public func addToken(_ token: ListedToken, for owner: String) async throws -> TokenList {
        try await tokenLists.add(token, for: owner)
    }

    /// Removes a token from an account's list and saves the list.
    ///
    /// - Parameters:
    ///   - mint: The mint address of the token to remove.
    ///   - owner: The account's wallet address.
    /// - Returns: The saved list.
    /// - Throws: ``TokenListError/unreadable`` if the saved list can't be read, or a file-system error if saving fails.
    public func removeToken(_ mint: Address, for owner: String) async throws -> TokenList {
        try await tokenLists.remove(mint, for: owner)
    }
}
