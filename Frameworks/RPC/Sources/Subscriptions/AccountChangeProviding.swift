/// A provider of confirmed wallet-account changes, independent of DAS and transaction submission.
public protocol AccountChangeProviding: Sendable {
    /// The network whose accounts are observed.
    var network: Network { get }

    /// Subscribes to SOL and owned SPL Token and Token-2022 account changes at confirmed commitment.
    ///
    /// Returns after all subscriptions are acknowledged. Notifications received during
    /// setup are retained. Slots are increasing, coalescing duplicate and older events;
    /// they signal that a consumer should reconcile its holdings, not patch balances.
    /// Cancel the task consuming the stream to close the connection. Errors terminate
    /// the stream without reconnecting automatically; consumers may explicitly start again.
    /// - Parameter owner: The wallet address whose SOL and token accounts to watch.
    /// - Returns: Confirmed change slots, buffered to retain the latest outstanding slot.
    /// - Throws: A sanitized subscription, transport, timeout, or cancellation error during setup.
    func changedSlots(for owner: String) async throws -> AsyncThrowingStream<UInt64, any Error>
}
