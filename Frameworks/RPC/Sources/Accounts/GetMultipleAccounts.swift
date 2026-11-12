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
    private let configuration: LedgerConfiguration

    /// Creates an account read at finalized commitment.
    ///
    /// - Parameters:
    ///   - addresses: One through 100 account addresses.
    ///   - minContextSlot: The minimum evaluation slot, or `nil` for no minimum.
    /// - Throws: ``GetMultipleAccountsError/invalidAddressCount`` for an empty or oversized request.
    init(addresses: [String], minContextSlot: UInt64? = nil) throws {
        guard (1...100).contains(addresses.count) else { throw GetMultipleAccountsError.invalidAddressCount }
        self.addresses = addresses
        configuration = LedgerConfiguration(minContextSlot: minContextSlot, includesAccountData: true)
    }

    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(addresses)
        try parameters.encode(configuration)
    }

    /// Checks that the response comes from the minimum slot or later and holds one entry per address.
    ///
    /// - Parameter response: The decoded response.
    /// - Throws: ``RPCError/InvalidResponse/staleContext`` if the response comes from an earlier slot, or
    ///   ``RPCError/InvalidResponse/mismatchedAccounts`` if it holds another number of accounts.
    public func validate(_ response: Response) throws {
        try configuration.validate(contextSlot: response.context.slot)
        guard response.value.count == addresses.count else { throw RPCError.invalidResponse(.mismatchedAccounts) }
    }
}
