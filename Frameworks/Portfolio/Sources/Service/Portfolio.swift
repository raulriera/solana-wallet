import Foundation
public import RPC
public import Transactions

/// A portfolio service that delivers persisted holdings and reads them again on request and after finalized changes.
public struct Portfolio: PortfolioProviding, TokenListProviding {
    private let coordinator: RefreshCoordinator
    private let observer: ObservationCoordinator
    private let tokenLists: TokenListCoordinator
    private let lookup: TokenLookup

    /// Creates a portfolio service that caches holdings in the app's cache directory
    /// and saves token lists in its Application Support directory.
    ///
    /// - Parameters:
    ///   - rpc: The RPC client that reads balances; every provider supports the request it uses.
    ///     A client that also hosts logo copies, such as Helius, adds logos to the listed tokens.
    ///     A client that also provides account subscriptions watches the accounts for finalized changes.
    ///   - prices: A same-network price provider; `nil` leaves holdings unpriced.
    /// - Precondition: `prices` serves the RPC client's network.
    public init(rpc: any RPC, prices: (any PriceProviding)? = nil) {
        self.init(rpc: rpc, store: FileSnapshotStore(directory: .cachesDirectory.appendingPathComponent("Portfolio")),
                  prices: prices)
    }

    /// Creates a service with injected stores.
    ///
    /// - Parameters:
    ///   - rpc: The RPC client that reads balances, and adds logos when it hosts logo copies.
    ///   - store: The persistent snapshot store.
    ///   - tokenLists: The token-list store; the default saves lists in Application Support.
    ///   - prices: An optional same-network price provider.
    ///   - changes: The optional finalized-change provider, defaulting to the RPC client's capability.
    ///   - pause: Cancellable scheduling for coalescing nearby changes and spacing reconnections.
    /// - Precondition: `prices` and `changes` serve the RPC client's network.
    init(rpc: any RPC, store: any SnapshotStoring,
         tokenLists: any TokenListStoring = FileTokenListStore(
            directory: .applicationSupportDirectory.appending(path: "Portfolio/TokenLists", directoryHint: .isDirectory)),
         prices: (any PriceProviding)? = nil,
         changes: (any AccountChangeProviding)? = nil,
         pause: @escaping ObservationCoordinator.Pause = { try await Task.sleep(for: $0) }) {
        let changes = changes ?? (rpc as? any AccountChangeProviding)
        // Quotes and changes describe one network's accounts, so a provider for another network is a wiring mistake.
        precondition(prices.map { $0.network == rpc.network } ?? true, "Prices must describe the RPC client's network.")
        precondition(changes.map { $0.network == rpc.network } ?? true,
                     "Account changes must describe the RPC client's network.")
        let lists = TokenListCoordinator(store: tokenLists, network: rpc.network)
        let logos = rpc as? any LogoProviding
        self.tokenLists = lists
        lookup = TokenLookup(rpc: rpc, logos: logos)
        coordinator = RefreshCoordinator(source: BalanceReader(rpc: rpc), tokenLists: lists, store: store,
                                         prices: prices, logos: logos)
        observer = ObservationCoordinator(refresh: coordinator, tokenLists: lists, changes: changes, pause: pause)
    }

    /// Returns cached state, then reads balances, logos, and prices again.
    ///
    /// The service owns cache lookup, persistence, and failure fallback.
    /// Each caller receives its own stream while concurrent callers share the refresh.
    /// Registration completes before this method returns; the refresh arrives through the stream.
    /// The reload also connects the wallet's observation again at once when it is disconnected.
    ///
    /// - Parameter owner: The wallet address whose holdings to retrieve.
    /// - Returns: A finite stream of complete states. Cancelling its consuming task
    ///   detaches that consumer without clearing cached data.
    public func updates(for owner: String) async -> AsyncStream<Update> {
        let updates = await coordinator.updates(for: owner)
        await observer.reconnect(for: owner)
        return updates
    }

    /// Observes finalized changes to the wallet and its listed token accounts, and reads balances again after each one.
    ///
    /// A dropped connection reports its error, then reconnects by itself and reads balances again.
    /// - Parameter owner: The visible wallet to observe until its consuming task is cancelled.
    /// - Returns: Cached state, an initial reload, event-driven refresh results, and connection errors.
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

    /// Ends the work that used the previous RPC provider and removes its logos from saved snapshots.
    ///
    /// Observation stops first, so no reconciliation can start a read with the previous provider's slot.
    /// - Throws: A file-system error if a saved snapshot's logos can't be removed.
    public func providerDidChange() async throws {
        await observer.stopAll()
        try await coordinator.providerDidChange()
    }

    /// Adds a token to an account's list and saves the list.
    ///
    /// An observed account then watches the new list and reads its balances once.
    /// - Parameters:
    ///   - token: The token to add; a token that's already listed changes nothing.
    ///   - owner: The account's wallet address.
    /// - Throws: ``TokenListError`` for a full or unreadable list, or a file-system error if saving fails.
    public func addToken(_ token: ListedToken, for owner: String) async throws {
        if try await tokenLists.add(token, for: owner) { await listChanged(for: owner) }
    }

    /// Removes a token from an account's list and saves the list.
    ///
    /// The cached holdings drop the token at once, so observers and later launches don't show it while
    /// balances are read again. An observed account then watches the new list and reads its balances once.
    /// - Parameters:
    ///   - mint: The mint address of the token to remove.
    ///   - owner: The account's wallet address.
    /// - Throws: ``TokenListError/unreadable`` if the saved list can't be read, or a file-system error if saving fails.
    public func removeToken(_ mint: Address, for owner: String) async throws {
        guard try await tokenLists.remove(mint, for: owner) else { return }
        // The saved list is already correct; cached holdings that can't be saved give way to the next read.
        try? await coordinator.removeHolding(.asset(mint.value), for: owner)
        await observer.restart(for: owner)
    }

    /// Looks up a token by its pasted mint address, so a person can check it before adding it.
    ///
    /// One standard RPC request reads the mint and its Metaplex metadata account, so every provider
    /// supports the lookup. A provider that hosts logo copies adds the logo.
    /// - Parameter mint: The pasted mint address.
    /// - Returns: The token to show and to pass to ``addToken(_:for:)``, with its logo when available.
    /// - Throws: ``TokenLookupError`` when the address isn't a fungible token mint, or a validation or RPC error.
    public func token(at mint: Address) async throws -> TokenPreview {
        try await lookup.preview(of: mint)
    }

    /// Reads and watches an account's balances again with its changed token list.
    ///
    /// A balance read in progress starts again first, so no read returns the previous list's balances.
    /// - Parameter owner: The account whose token list changed.
    private func listChanged(for owner: String) async {
        await coordinator.restartBalanceRead(for: owner)
        await observer.restart(for: owner)
    }
}
