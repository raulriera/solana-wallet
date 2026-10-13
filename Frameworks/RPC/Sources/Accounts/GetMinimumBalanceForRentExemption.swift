/// Reads the rent-exempt deposit for an account's allocated data size.
public struct GetMinimumBalanceForRentExemption: RPCRequest {
    /// The provider-neutral JSON-RPC method name.
    public static let method = "getMinimumBalanceForRentExemption"
    /// The minimum balance in lamports.
    public typealias Response = UInt64

    private let dataLength: UInt64

    /// Creates a rent query at finalized commitment for the account that preparation intends to allocate.
    ///
    /// This method doesn't return a slot or support a minimum context slot.
    ///
    /// - Parameter dataLength: The account's allocated data size in bytes.
    public init(dataLength: UInt64) {
        self.dataLength = dataLength
    }

    /// Encodes the size and finalized commitment as positional parameters.
    ///
    /// - Parameter encoder: The encoder receiving the parameter array.
    /// - Throws: An encoding error if the parameters cannot be represented.
    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(dataLength)
        try parameters.encode(["commitment": Commitment.finalized])
    }
}
