/// A provider of a sent transaction's landing and of new roots, independent of transaction submission.
public protocol SignatureEventProviding: Sendable {
    /// The network whose transactions are watched.
    var network: Network { get }

    /// Subscribes to one signature at finalized commitment and to new roots, on one connection.
    ///
    /// Returns after both subscriptions are acknowledged. The stream keeps every unread event,
    /// including notifications received during setup, so a later root never replaces a landing.
    /// Roots are increasing, skipping duplicate and older ones. Cancel the task consuming the stream
    /// to close the connection. Errors terminate the stream without reconnecting automatically;
    /// consumers may explicitly start again.
    /// - Parameter signature: The base-58 encoded signature of a sent transaction.
    /// - Returns: The transaction's landing and new roots, in the order they arrive.
    /// - Throws: A sanitized subscription, transport, timeout, or cancellation error during setup.
    func events(for signature: String) async throws -> AsyncThrowingStream<SignatureEvent, any Error>
}
