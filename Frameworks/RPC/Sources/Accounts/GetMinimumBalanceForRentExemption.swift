/// Reads the rent-exempt deposit for an account's allocated data size.
public struct GetMinimumBalanceForRentExemption: RPCRequest {
    /// The provider-neutral JSON-RPC method name.
    public static let method = "getMinimumBalanceForRentExemption"
    /// The minimum balance in lamports.
    public typealias Response = UInt64

    private let dataLength: UInt64
    private let commitment: Commitment

    /// Creates a rent query for the account that preparation intends to allocate.
    ///
    /// This method doesn't return a slot or support a minimum context slot.
    ///
    /// - Parameters:
    ///   - dataLength: The account's allocated data size in bytes.
    ///   - commitment: The confirmation level, defaulting to `confirmed`.
    public init(dataLength: UInt64, commitment: Commitment = .confirmed) {
        self.dataLength = dataLength
        self.commitment = commitment
    }

    /// Encodes the size and commitment as positional parameters.
    ///
    /// - Parameter encoder: The encoder receiving the parameter array.
    /// - Throws: An encoding error if the parameters cannot be represented.
    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(dataLength)
        try parameters.encode(["commitment": commitment])
    }
}
