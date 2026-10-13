/// A request for the current block height at a given confirmation level.
public struct GetBlockHeight: RPCRequest {
    /// The JSON-RPC method name for retrieving the current block height.
    public static let method = "getBlockHeight"

    /// The current block height, which is distinct from the ledger slot.
    public typealias Response = UInt64

    /// The confirmation level requested for the block height.
    public let commitment: Commitment

    /// The earliest slot at which the node may evaluate the request, or `nil` for no minimum.
    public let minContextSlot: UInt64?

    /// Creates a request for the current block height.
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
