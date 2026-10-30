/// A request for several accounts at one ledger context.
public struct GetMultipleAccounts: RPCRequest {
    public static let method = "getMultipleAccounts"

    /// The accounts in request order, with their ledger context.
    public struct Response: Decodable, Sendable {
        public let context: Context
        /// The accounts in request order, or `nil` for a missing account.
        public let value: [Account?]
    }

    /// The addresses to read, in response order.
    public let addresses: [String]
    private let minContextSlot: UInt64?

    /// Creates an account read at finalized commitment.
    ///
    /// - Parameters:
    ///   - addresses: One through 100 account addresses.
    ///   - minContextSlot: The minimum evaluation slot, or `nil` for no minimum.
    /// - Throws: ``GetMultipleAccountsError/invalidAddressCount`` for an empty or oversized request.
    public init(addresses: [String], minContextSlot: UInt64? = nil) throws {
        guard (1...100).contains(addresses.count) else { throw GetMultipleAccountsError.invalidAddressCount }
        self.addresses = addresses
        self.minContextSlot = minContextSlot
    }

    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(addresses)
        try parameters.encode(LedgerConfiguration(minContextSlot: minContextSlot, includesAccountData: true))
    }
}
