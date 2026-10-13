/// A request for a recent blockhash and the block height through which it remains valid.
public struct GetLatestBlockhash: RPCRequest {
    /// The JSON-RPC method name for retrieving the latest blockhash.
    public static let method = "getLatestBlockhash"

    /// A blockhash and its expiry, together with the ledger context in which they were read.
    public struct Response: Decodable, Sendable {
        /// The ledger context associated with the returned blockhash.
        public let context: Context

        /// The blockhash and its last valid block height.
        public let value: Value

        /// Creates a blockhash response with its ledger context.
        ///
        /// - Parameters:
        ///   - context: The ledger context associated with the blockhash.
        ///   - value: The blockhash and its last valid block height.
        public init(context: Context, value: Value) {
            self.context = context
            self.value = value
        }
    }

    /// A recent blockhash and the block height through which transactions may use it.
    public struct Value: Decodable, Sendable, Equatable {
        /// The base-58 encoded blockhash to include in a transaction.
        public let blockhash: String

        /// The last block height at which the blockhash is valid, inclusive.
        ///
        /// Compare this value with `GetBlockHeight`, not with the response's slot.
        public let lastValidBlockHeight: UInt64

        /// Creates a blockhash with its expiry height.
        ///
        /// - Parameters:
        ///   - blockhash: The base-58 encoded blockhash.
        ///   - lastValidBlockHeight: The last block height at which the blockhash is valid.
        public init(blockhash: String, lastValidBlockHeight: UInt64) {
            self.blockhash = blockhash
            self.lastValidBlockHeight = lastValidBlockHeight
        }
    }

    /// The confirmation level requested for the blockhash.
    public let commitment: Commitment

    /// The earliest slot at which the node may evaluate the request, or `nil` for no minimum.
    public let minContextSlot: UInt64?

    /// Creates a request for the latest blockhash and its expiry height.
    ///
    /// - Parameters:
    ///   - commitment: The confirmation level to query. The default is `finalized`.
    ///   - minContextSlot: The minimum evaluation slot. The default is `nil`.
    public init(commitment: Commitment = .finalized, minContextSlot: UInt64? = nil) {
        self.commitment = commitment
        self.minContextSlot = minContextSlot
    }

    /// Encodes the ledger configuration as positional RPC parameters.
    ///
    /// - Parameter encoder: The encoder that receives the parameter array.
    /// - Throws: An encoding error if the encoder can't represent a parameter.
    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(LedgerConfiguration(commitment: commitment, minContextSlot: minContextSlot))
    }
}
