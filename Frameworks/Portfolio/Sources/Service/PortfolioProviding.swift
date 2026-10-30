/// A type that provides wallet portfolios with caching and refreshes.
public protocol PortfolioProviding: Sendable {
    /// Observes finalized account changes for the lifetime of the consuming task.
    ///
    /// - Parameter owner: The wallet address.
    /// - Returns: A stream of cached state, refresh results, and connection errors.
    func observations(for owner: String) async -> AsyncStream<Update>

    /// Returns cached portfolio state and reads balances, logos, and prices again.
    ///
    /// - Parameter owner: The wallet address.
    /// - Returns: The cached state while the refresh runs, followed by a completed or failed refresh.
    func updates(for owner: String) async -> AsyncStream<Update>

    /// Reads an observed wallet's balances, logos, and prices again.
    ///
    /// - Parameter owner: The observed wallet's address.
    func reload(for owner: String) async

    /// Removes a wallet's local portfolio data and cancels its refresh.
    ///
    /// - Parameter owner: The wallet address.
    /// - Throws: A file-system error.
    func removeData(for owner: String) async throws

    /// Ends the work that used the previous RPC provider and removes its logos from saved snapshots.
    ///
    /// - Throws: A file-system error.
    func providerDidChange() async throws

    /// Reads every observed wallet's balances and prices again after a price change.
    func pricesDidChange() async
}
