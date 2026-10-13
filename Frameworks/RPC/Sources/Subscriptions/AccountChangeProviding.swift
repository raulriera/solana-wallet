/// A provider of finalized account changes, independent of DAS and transaction submission.
public protocol AccountChangeProviding: Sendable {
    /// The network whose accounts are observed.
    var network: Network { get }

    /// Subscribes to each account's changes at finalized commitment, on one connection.
    ///
    /// Returns after all subscriptions are acknowledged. Notifications received during
    /// setup are retained. An account that doesn't exist yet notifies when it's created.
    /// Slots are increasing, coalescing duplicate and older events;
    /// they signal that a consumer should reconcile its holdings, not patch balances.
    /// Cancel the task consuming the stream to close the connection. Errors terminate
    /// the stream without reconnecting automatically; consumers may explicitly start again.
    /// - Parameter addresses: The accounts to watch; a repeated address is watched once.
    /// - Returns: Finalized change slots, buffered to retain the latest outstanding slot.
    /// - Throws: A sanitized subscription, transport, timeout, or cancellation error during setup.
    func changedSlots(for addresses: [String]) async throws -> AsyncThrowingStream<UInt64, any Error>
}
