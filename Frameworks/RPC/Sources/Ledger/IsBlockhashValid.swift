/// A request that checks whether a recent blockhash is still valid.
public struct IsBlockhashValid: RPCRequest {
    public static let method = "isBlockhashValid"

    /// The validity of a blockhash at a ledger context.
    public struct Response: Decodable, Sendable {
        public let context: Context
        /// Whether the blockhash is valid.
        public let value: Bool
    }

    /// The base-58 encoded blockhash.
    public let blockhash: String
    /// The earliest slot at which the node may evaluate the request, or `nil` for no minimum.
    public let minContextSlot: UInt64?

    /// Creates a validity request at finalized commitment.
    ///
    /// - Parameters:
    ///   - blockhash: The base-58 encoded blockhash.
    ///   - minContextSlot: The earliest evaluation slot, or `nil` for no minimum.
    public init(blockhash: String, minContextSlot: UInt64? = nil) {
        self.blockhash = blockhash
        self.minContextSlot = minContextSlot
    }

    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(blockhash)
        try parameters.encode(LedgerConfiguration(minContextSlot: minContextSlot))
    }
}
