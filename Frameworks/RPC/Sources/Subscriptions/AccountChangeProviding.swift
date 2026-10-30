/// A provider of finalized account changes.
public protocol AccountChangeProviding: Sendable {
    var network: Network { get }

    /// Subscribes to each account's changes at finalized commitment on one connection.
    ///
    /// - Parameter addresses: The accounts to watch.
    /// - Returns: Increasing finalized change slots.
    /// - Throws: An ``RPCError`` or `CancellationError`.
    func changedSlots(for addresses: [String]) async throws -> AsyncThrowingStream<UInt64, any Error>
}
