/// A request to check a supplied recent blockhash without replacing it.
public struct IsBlockhashValid: RPCRequest {
    /// The JSON-RPC method name for checking recent-blockhash validity.
    public static let method = "isBlockhashValid"

    /// Whether the hash remains valid at the returned ledger context.
    public struct Response: Decodable, Sendable {
        /// The ledger context in which validity was evaluated.
        public let context: Context
        /// Whether the hash is in the node's recent-blockhash queue.
        public let value: Bool

        /// Creates a blockhash validity observation.
        ///
        /// - Parameters:
        ///   - context: The ledger context of the observation.
        ///   - value: Whether the supplied recent blockhash remains valid.
        public init(context: Context, value: Bool) {
            self.context = context
            self.value = value
        }
    }

    /// The Base58 recent blockhash whose validity to check.
    public let blockhash: String
    /// The confirmation level used to evaluate the blockhash.
    public let commitment: Commitment
    /// The minimum ledger slot to evaluate, or `nil` for no minimum.
    public let minContextSlot: UInt64?

    /// Creates a validity request without asserting durable-nonce validity.
    ///
    /// - Parameters:
    ///   - blockhash: The encoded recent blockhash to check.
    ///   - commitment: The confirmation level. The default is `confirmed`.
    ///   - minContextSlot: The earliest evaluation slot. The default is `nil`.
    public init(blockhash: String, commitment: Commitment = .confirmed, minContextSlot: UInt64? = nil) {
        self.blockhash = blockhash
        self.commitment = commitment
        self.minContextSlot = minContextSlot
    }

    /// Encodes the blockhash and ledger configuration as positional parameters.
    ///
    /// - Parameter encoder: The encoder receiving the RPC parameter array.
    /// - Throws: An encoding error if the parameters can't be represented.
    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(blockhash)
        try parameters.encode(LedgerConfiguration(commitment: commitment, minContextSlot: minContextSlot))
    }
}
