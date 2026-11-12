/// A request for a recent blockhash and the block height through which it remains valid.
public struct GetLatestBlockhash: ContextualRequest {
    public static let method = "getLatestBlockhash"

    /// A blockhash and its expiry, with the ledger context in which they were read.
    public struct Response: Decodable, Sendable, ContextualResponse {
        public let context: Context

        public let value: Value

        /// Creates a blockhash response with its ledger context.
        ///
        /// - Parameters:
        ///   - context: The ledger context of the blockhash.
        ///   - value: The blockhash and its last valid block height.
        public init(context: Context, value: Value) {
            self.context = context
            self.value = value
        }
    }

    /// A recent blockhash and the block height through which transactions may use it.
    public struct Value: Decodable, Sendable, Equatable {
        /// The base-58 encoded blockhash.
        public let blockhash: String

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

    /// The earliest slot at which the node may evaluate the request, or `nil` for no minimum.
    public let minContextSlot: UInt64?

    /// Creates a request for the latest finalized blockhash and its expiry height.
    ///
    /// - Parameter minContextSlot: The earliest evaluation slot, or `nil` for no minimum.
    public init(minContextSlot: UInt64? = nil) {
        self.minContextSlot = minContextSlot
    }

    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(LedgerConfiguration(minContextSlot: minContextSlot))
    }
}
