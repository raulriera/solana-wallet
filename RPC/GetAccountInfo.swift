/// A request for an account's state and binary data.
public struct GetAccountInfo: RPCRequest {
    /// The JSON-RPC method name for retrieving account information.
    public static let method = "getAccountInfo"

    /// An account and the ledger context in which it was read.
    public struct Response: Decodable, Sendable {
        /// The ledger context associated with the account lookup.
        public let context: Context

        /// The requested account, or `nil` if it doesn't exist at the requested commitment.
        public let value: Account?

        /// Creates an account lookup result with its ledger context.
        ///
        /// - Parameters:
        ///   - context: The ledger context associated with the lookup.
        ///   - value: The requested account, or `nil` if it doesn't exist.
        public init(context: Context, value: Account?) {
            self.context = context
            self.value = value
        }

        /// Creates a lookup result by decoding its context and nullable account.
        ///
        /// - Parameter decoder: The decoder containing the lookup result.
        /// - Throws: A decoding error if a required field is missing or malformed.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            context = try container.decode(Context.self, forKey: .context)
            value = try container.decode(Account?.self, forKey: .value)
        }

        /// The field names in an account lookup result.
        private enum CodingKeys: String, CodingKey {
            case context, value
        }
    }

    /// The base-58 encoded account address to query.
    public let address: String

    /// The confirmation level requested for the account state.
    public let commitment: Commitment

    /// Creates a request for an account's state and binary data.
    ///
    /// - Parameters:
    ///   - address: The base-58 encoded account address. The server validates this value.
    ///   - commitment: The confirmation level to query. The default is `confirmed`.
    public init(address: String, commitment: Commitment = .confirmed) {
        self.address = address
        self.commitment = commitment
    }

    /// Encodes the address, commitment, and base64 encoding as positional RPC parameters.
    ///
    /// - Parameter encoder: The encoder that receives the parameter array.
    /// - Throws: An encoding error if the encoder can't represent a parameter.
    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(address)
        try parameters.encode(AccountConfiguration(commitment: commitment))
    }
}
