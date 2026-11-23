public import Foundation
public import RPC
public import Transactions

/// A service that delivers saved holdings and reads them again on request and after finalized changes.
public struct Portfolio: PortfolioProviding, TokenListProviding {
    private let coordinator: RefreshCoordinator
    private let observer: ObservationCoordinator
    private let tokenLists: TokenListCoordinator
    private let lookup: TokenLookup

    /// Creates a portfolio service that saves token lists and caches holdings in the given directories.
    ///
    /// - Parameters:
    ///   - rpc: The RPC client that reads balances, watches finalized account changes, and, when it has the logos
    ///     capability, reads token logos.
    ///   - prices: The price provider for the RPC client's network, or `nil` for no prices.
    ///   - tokenListDirectory: The directory that saves token lists.
    ///   - cacheDirectory: The directory that caches holdings.
    public init(
        rpc: any LogoProviding & AccountChangeProviding,
        prices: (any PriceProviding)? = nil,
        tokenListDirectory: URL,
        cacheDirectory: URL
    ) {
        self.init(rpc: rpc, store: FileSnapshotStore(directory: cacheDirectory),
                  tokenLists: FileTokenListStore(directory: tokenListDirectory), prices: prices)
    }

    /// Creates a service with injected stores.
    ///
    /// - Parameters:
    ///   - rpc: The RPC client that reads balances, watches finalized account changes, and, when it has the logos
    ///     capability, reads token logos.
    ///   - store: The snapshot store.
    ///   - tokenLists: The token-list store.
    ///   - prices: The price provider, or `nil` for no prices.
    ///   - clock: The clock that times change coalescing and reconnection waits.
    init(rpc: any LogoProviding & AccountChangeProviding, store: any SnapshotStoring,
         tokenLists: FileTokenListStore,
         prices: (any PriceProviding)? = nil,
         clock: any Clock<Duration> = ContinuousClock()) {
        precondition(prices.map { $0.network == rpc.network } ?? true, "Prices must describe the RPC client's network.")
        let lists = TokenListCoordinator(store: tokenLists, network: rpc.network)
        self.tokenLists = lists
        lookup = TokenLookup(rpc: rpc)
        coordinator = RefreshCoordinator(source: BalanceReader(rpc: rpc), tokenLists: lists, store: store,
                                         prices: prices, logos: rpc)
        observer = ObservationCoordinator(refresh: coordinator, tokenLists: lists, changes: rpc, clock: clock)
    }

    public func updates(for owner: String) async -> AsyncStream<Update> {
        let updates = await coordinator.updates(for: owner)
        await observer.reconnect(for: owner)
        return updates
    }

    public func reload(for owner: String) async {
        await observer.reload(for: owner)
    }

    public func observations(for owner: String) async -> AsyncStream<Update> {
        await observer.observations(for: owner)
    }

    public func removeData(for owner: String) async throws {
        await observer.stop(for: owner)
        try await coordinator.removeData(for: owner)
        try await tokenLists.removeList(for: owner)
    }

    public func providerDidChange() async throws {
        await observer.stopAll()
        try await coordinator.providerDidChange()
    }

    public func pricesDidChange() async {
        await coordinator.restartBalanceReads()
        await observer.restartAll()
    }

    public func addToken(_ mint: Mint, for owner: String) async throws {
        if try await tokenLists.add(mint, for: owner) { await listChanged(for: owner) }
    }

    public func removeToken(_ mint: Address, for owner: String) async throws {
        guard try await tokenLists.remove(mint, for: owner) else { return }
        try? await coordinator.removeHolding(.token(mint: mint), for: owner)
        await observer.restart(for: owner)
    }

    public func token(at mint: Address) async throws -> TokenPreview {
        try await lookup.preview(of: mint)
    }

    /// Reads and watches an account's balances again with its changed token list.
    ///
    /// - Parameter owner: The account whose token list changed.
    private func listChanged(for owner: String) async {
        await coordinator.restartBalanceRead(for: owner)
        await observer.restart(for: owner)
    }
}
