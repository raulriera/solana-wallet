/// A request for an owner's token accounts matching a mint or token program.
public struct GetTokenAccountsByOwner: RPCRequest {
    /// The JSON-RPC method name for retrieving an owner's token accounts.
    public static let method = "getTokenAccountsByOwner"

    /// A filter that selects token accounts by exactly one mint or token program.
    public enum Filter: Encodable, Sendable {
        /// Selects accounts for the token mint at the given base-58 encoded address.
        case mint(String)

        /// Selects accounts owned by the token program at the given base-58 encoded address.
        case program(String)

        /// Encodes the filter as a single mint or program identifier field.
        ///
        /// - Parameter encoder: The encoder that receives the filter object.
        /// - Throws: An encoding error if the encoder can't represent the filter.
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .mint(let address):
                try container.encode(address, forKey: .mint)
            case .program(let address):
                try container.encode(address, forKey: .programId)
            }
        }

        /// The field names accepted by the token account filter.
        private enum CodingKeys: String, CodingKey {
            case mint, programId
        }
    }

    /// Matching token accounts and the ledger context in which they were read.
    public struct Response: Decodable, Sendable {
        /// The ledger context associated with the token account lookup.
        public let context: Context

        /// The matching accounts and their addresses, or an empty array if none match.
        public let value: [AccountEntry]

        /// Creates token account lookup results with their ledger context.
        ///
        /// - Parameters:
        ///   - context: The ledger context associated with the lookup.
        ///   - value: The matching accounts and their addresses.
        public init(context: Context, value: [AccountEntry]) {
            self.context = context
            self.value = value
        }
    }

    /// The base-58 encoded address of the token-account owner to query.
    public let owner: String

    /// The mint or token program used to select matching accounts.
    public let filter: Filter

    /// The confirmation level requested for the account state.
    public let commitment: Commitment

    /// Creates a request for an owner's token accounts matching the given filter.
    ///
    /// - Parameters:
    ///   - owner: The base-58 encoded address of the token-account owner.
    ///     The server validates this address.
    ///   - filter: The mint or token program to match. The server validates its address.
    ///   - commitment: The confirmation level to query. The default is `confirmed`.
    public init(owner: String, filter: Filter, commitment: Commitment = .confirmed) {
        self.owner = owner
        self.filter = filter
        self.commitment = commitment
    }

    /// Encodes the owner, filter, and shared account configuration as positional RPC parameters.
    ///
    /// - Parameter encoder: The encoder that receives the parameter array.
    /// - Throws: An encoding error if the encoder can't represent a parameter.
    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(owner)
        try parameters.encode(filter)
        try parameters.encode(AccountConfiguration(commitment: commitment))
    }
}
