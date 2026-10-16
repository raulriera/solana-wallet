/// A transaction of a shielded pool, with the outputs and nullifiers that it published.
///
/// A confidential transaction carries its transaction viewing key and salt, which decrypt its outputs'
/// notes. A proofless deposit carries neither, has one output, and spends no nullifiers.
public struct ShieldedTransaction: Sendable, Equatable {
    /// The transaction's base-58 signature.
    public let signature: String
    /// The slot that included the transaction.
    public let slot: UInt64
    /// The position of the shielded-pool event within the transaction, when the indexer reports it.
    public let eventIndex: UInt16?
    /// The 33-byte compressed P-256 transaction viewing public key, or `nil` without encrypted notes.
    public let transactionViewingKey: [UInt8]?
    /// The 16-byte salt that all of the transaction's note ciphertexts share, or `nil` without encrypted notes.
    public let salt: [UInt8]?
    /// The outputs in slot order.
    public let outputs: [ShieldedOutput]
    /// The 32-byte nullifiers of the UTXOs that the transaction spent.
    public let nullifiers: [[UInt8]]
    /// Whether the transaction is a proofless deposit.
    public let isProofless: Bool

    /// Creates a transaction from its published fields.
    ///
    /// - Parameters:
    ///   - signature: The base-58 signature.
    ///   - slot: The slot that included the transaction.
    ///   - eventIndex: The event's position within the transaction, or `nil` when unknown.
    ///   - transactionViewingKey: The 33-byte transaction viewing public key, or `nil`.
    ///   - salt: The 16-byte note salt, or `nil`.
    ///   - outputs: The outputs in slot order.
    ///   - nullifiers: The 32-byte nullifiers that the transaction spent.
    ///   - isProofless: Whether the transaction is a proofless deposit.
    public init(
        signature: String,
        slot: UInt64,
        eventIndex: UInt16?,
        transactionViewingKey: [UInt8]?,
        salt: [UInt8]?,
        outputs: [ShieldedOutput],
        nullifiers: [[UInt8]],
        isProofless: Bool
    ) {
        self.signature = signature
        self.slot = slot
        self.eventIndex = eventIndex
        self.transactionViewingKey = transactionViewingKey
        self.salt = salt
        self.outputs = outputs
        self.nullifiers = nullifiers
        self.isProofless = isProofless
    }
}
