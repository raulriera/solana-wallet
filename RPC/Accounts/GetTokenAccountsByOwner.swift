/// Finds owned token accounts without downloading their token or extension data.
public struct GetTokenAccountsByOwner: RPCRequest {
    /// The provider-neutral method name.
    public static let method = "getTokenAccountsByOwner"

    /// Token account identities and metadata observed at one ledger context.
    public struct Response: Decodable, Sendable {
        /// The observation slot and optional API version.
        public let context: Context
        /// Accounts whose token authority matches the requested owner.
        public let value: [Entry]
    }

    /// An owned token account; its data is empty because the request selects no bytes.
    public struct Entry: Decodable, Sendable {
        /// The token account's public address.
        public let address: String
        /// Program ownership, lamports, and executable status; token data is omitted.
        public let account: Account

        private enum CodingKeys: String, CodingKey { case address = "pubkey", account }
    }

    private let owner: String
    private let program: String
    private let commitment: Commitment
    private let minContextSlot: UInt64?

    /// Creates a token ownership lookup for one token program.
    /// - Parameters:
    ///   - owner: The Base58 wallet authority to discover accounts for.
    ///   - program: The SPL Token or Token-2022 program address.
    ///   - commitment: The required confirmation level, defaulting to `confirmed`.
    ///   - minContextSlot: The earliest acceptable observation slot, or `nil`.
    public init(owner: String, program: String, commitment: Commitment = .confirmed, minContextSlot: UInt64? = nil) {
        self.owner = owner
        self.program = program
        self.commitment = commitment
        self.minContextSlot = minContextSlot
    }

    /// Encodes a program filter and an empty base64 data slice for efficient discovery.
    /// - Parameter encoder: The encoder receiving positional parameters.
    /// - Throws: An encoding error.
    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(owner)
        try parameters.encode(["programId": program])
        var options = parameters.nestedContainer(keyedBy: CodingKeys.self)
        try options.encode("base64", forKey: .encoding)
        try options.encode(["offset": 0, "length": 0], forKey: .dataSlice)
        try options.encode(commitment, forKey: .commitment)
        try options.encodeIfPresent(minContextSlot, forKey: .minContextSlot)
    }

    private enum CodingKeys: String, CodingKey { case encoding, dataSlice, commitment, minContextSlot }
}
