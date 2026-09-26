/// A type that provides wallet portfolios while encapsulating caching and refreshes.
public protocol PortfolioProviding: Sendable {
    /// Returns existing portfolio state followed by the outcome of one automatic refresh.
    ///
    /// - Parameter owner: The wallet address whose portfolio to retrieve.
    /// - Returns: A finite sequence containing initial state and, unless cancelled,
    ///   a completed or failed refresh. Failures retain the preceding snapshot.
    func updates(for owner: String) -> AsyncStream<Update>

    /// Removes locally retained portfolio data and cancels its active refresh.
    ///
    /// - Parameter owner: The wallet whose local data to remove.
    /// - Throws: A file-system error if the stored snapshot can't be removed.
    func removeData(for owner: String) async throws
}
