/// Reads related accounts at one ledger context.
public struct GetMultipleAccounts: RPCRequest {
    /// The provider-neutral JSON-RPC method name.
    public static let method = "getMultipleAccounts"

    /// Ordered account observations, retaining missing accounts as `nil`.
    public struct Response: Decodable, Sendable {
        /// The shared slot at which the accounts were evaluated.
        public let context: Context
        /// Account values corresponding to the requested addresses in order.
        public let value: [Account?]
    }

    /// The addresses to retrieve in the same order as the response values.
    public let addresses: [String]
    private let minContextSlot: UInt64?

    /// Creates one bounded account read at finalized commitment, without chunking into inconsistent contexts.
    ///
    /// - Parameters:
    ///   - addresses: One through 100 account addresses.
    ///   - minContextSlot: The earliest acceptable observation slot, or `nil`.
    /// - Throws: ``GetMultipleAccountsError/invalidAddressCount`` for an empty or oversized request.
    public init(addresses: [String], minContextSlot: UInt64? = nil) throws {
        guard (1...100).contains(addresses.count) else { throw GetMultipleAccountsError.invalidAddressCount }
        self.addresses = addresses
        self.minContextSlot = minContextSlot
    }

    /// Requests base64 account bytes at finalized commitment and the chosen minimum slot.
    ///
    /// - Parameter encoder: The encoder receiving positional RPC parameters.
    /// - Throws: An encoding error if the parameters cannot be represented.
    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(addresses)
        var options = parameters.nestedContainer(keyedBy: CodingKeys.self)
        try options.encode("base64", forKey: .encoding)
        try options.encode(Commitment.finalized, forKey: .commitment)
        try options.encodeIfPresent(minContextSlot, forKey: .minContextSlot)
    }

    private enum CodingKeys: String, CodingKey { case encoding, commitment, minContextSlot }
}
