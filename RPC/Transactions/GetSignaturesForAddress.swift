/// Looks for the most recent available transaction referencing an address.
///
/// Empty results describe the provider's available history, not proof that an address was never used.
public struct GetSignaturesForAddress: RPCRequest {
    /// The provider-neutral method name.
    public static let method = "getSignaturesForAddress"
    /// At most one available transaction, including transactions that failed execution.
    public typealias Response = [Signature]

    /// The identity and execution outcome of a transaction referencing the address.
    public struct Signature: Decodable, Sendable {
        /// The Base58 transaction signature.
        public let signature: String
        /// The slot containing the transaction.
        public let slot: UInt64
        /// The execution failure, or `nil` for successful execution.
        public let error: TransactionError?

        /// Decodes the signature and its required, nullable execution outcome.
        /// - Parameter decoder: The decoder containing a signature observation.
        /// - Throws: A decoding error for missing or malformed fields.
        public init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            signature = try values.decode(String.self, forKey: .signature)
            slot = try values.decode(UInt64.self, forKey: .slot)
            error = try values.decode(TransactionError?.self, forKey: .error)
        }

        private enum CodingKeys: String, CodingKey { case signature, slot, error = "err" }
    }

    private let address: String
    private let commitment: Commitment
    private let minContextSlot: UInt64?

    /// Creates a bounded history lookup for account discovery.
    /// - Parameters:
    ///   - address: The Base58 account address to inspect.
    ///   - commitment: The confirmation level, defaulting to `confirmed`.
    ///   - minContextSlot: The minimum node context; this does not filter transaction history by slot.
    public init(address: String, commitment: Commitment = .confirmed, minContextSlot: UInt64? = nil) {
        self.address = address
        self.commitment = commitment
        self.minContextSlot = minContextSlot
    }

    /// Requests one signature without downloading transaction bodies or paginating history.
    /// - Parameter encoder: The encoder receiving positional parameters.
    /// - Throws: An encoding error.
    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(address)
        var options = parameters.nestedContainer(keyedBy: CodingKeys.self)
        try options.encode(1, forKey: .limit)
        try options.encode(commitment, forKey: .commitment)
        try options.encodeIfPresent(minContextSlot, forKey: .minContextSlot)
    }

    private enum CodingKeys: String, CodingKey { case limit, commitment, minContextSlot }
}
