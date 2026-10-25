/// A type that provides wallet portfolios while encapsulating caching and refreshes.
///
/// Assign increasing `Update.revision` values across all streams from one provider instance.
/// Forwarded or replayed updates keep their revision; cached snapshots retain their original
/// `Update.snapshotRevision` until a provider change. Consumers can then order data and status
/// independently of wall time.
public protocol PortfolioProviding: Sendable {
    /// Observes finalized changes to the wallet and its listed token accounts until the consuming task is
    /// cancelled, reading balances again after each.
    ///
    /// Connection errors are reported; dropped connections reconnect with increasing delays, and refusals
    /// wait for a reload, a token-list change, or a new consumer.
    ///
    /// - Parameter owner: The wallet whose holdings to observe.
    /// - Returns: A stream of cached state, refresh results, and connection errors, ending on cancellation,
    ///   data removal, or a provider change.
    func observations(for owner: String) async -> AsyncStream<Update>

    /// Returns cached portfolio state and reads balances, logos, and prices again.
    ///
    /// The consumer is registered before this method returns. Network results arrive through the stream.
    /// The reload also connects the wallet's observation again at once when it is disconnected.
    ///
    /// - Parameter owner: The wallet address whose portfolio to retrieve.
    /// - Returns: The cached state while the refresh runs, followed by a completed or failed refresh.
    ///   Failures retain the latest complete snapshot.
    func updates(for owner: String) async -> AsyncStream<Update>

    /// Removes locally retained portfolio data and cancels its active refresh.
    ///
    /// - Parameter owner: The wallet whose local data to remove.
    /// - Throws: A file-system error if the stored snapshot or token list can't be removed.
    func removeData(for owner: String) async throws

    /// Ends the work that used the previous RPC provider and removes its logos from saved snapshots.
    ///
    /// Call this after the RPC client starts to use the new provider, then observe again.
    /// Observations and refreshes end without a further update, which closes their subscriptions.
    /// Cached snapshots keep their balances and prices, lose their logos, and arrive with a newer
    /// `Update.snapshotRevision`, so consumers replace copies that show the previous provider's logos.
    /// The next balance read doesn't require an earlier finalized slot and looks up logos from the new provider.
    /// - Throws: A file-system error if a saved snapshot's logos can't be removed; the work ends regardless.
    func providerDidChange() async throws
}
