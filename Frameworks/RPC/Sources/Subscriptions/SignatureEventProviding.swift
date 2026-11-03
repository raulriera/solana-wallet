/// A provider of a sent transaction's landing and of new roots.
public protocol SignatureEventProviding: Sendable {
    /// Subscribes to one signature at finalized commitment and to new roots on one connection.
    ///
    /// - Parameter signature: The base-58 encoded signature of a sent transaction.
    /// - Returns: The transaction's landing and new roots, in the order they arrive.
    /// - Throws: An ``RPCError`` or `CancellationError`.
    func events(for signature: String) async throws -> AsyncThrowingStream<SignatureEvent, any Error>
}
