/// A request for the current block height at finalized commitment.
public struct GetBlockHeight: RPCRequest {
    public static let method = "getBlockHeight"

    public typealias Response = UInt64

    /// The earliest slot at which the node may evaluate the request, or `nil` for no minimum.
    public let minContextSlot: UInt64?

    /// Creates a request for the current finalized block height.
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
