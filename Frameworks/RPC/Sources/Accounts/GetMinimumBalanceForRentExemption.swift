/// A request for the rent-exempt minimum balance of an account's data size.
public struct GetMinimumBalanceForRentExemption: RPCRequest {
    public static let method = "getMinimumBalanceForRentExemption"
    public typealias Response = UInt64

    private let dataLength: UInt64

    /// Creates a rent query at finalized commitment.
    ///
    /// - Parameter dataLength: The account's allocated data size in bytes.
    public init(dataLength: UInt64) {
        self.dataLength = dataLength
    }

    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(dataLength)
        try parameters.encode(LedgerConfiguration())
    }
}
