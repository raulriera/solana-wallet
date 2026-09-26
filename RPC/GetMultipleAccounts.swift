/// A request for multiple accounts' state and binary data in one HTTP call.
public struct GetMultipleAccounts: RPCRequest {
    /// The JSON-RPC method name for retrieving multiple accounts.
    public static let method = "getMultipleAccounts"

    /// Accounts in request order and the ledger context in which they were read.
    public struct Response: Decodable, Sendable {
        /// The ledger context associated with the account lookups.
        public let context: Context

        /// The requested accounts in address order, with `nil` for accounts that don't exist.
        public let value: [Account?]

        /// Creates account lookup results with their ledger context.
        ///
        /// - Parameters:
        ///   - context: The ledger context associated with the lookups.
        ///   - value: The accounts in request order, retaining `nil` for missing accounts.
        public init(context: Context, value: [Account?]) {
            self.context = context
            self.value = value
        }
    }

    /// The base-58 encoded account addresses to query, in response order.
    public let addresses: [String]

    /// The confirmation level requested for the account state.
    public let commitment: Commitment

    /// Creates a request for up to 100 accounts' state and binary data.
    ///
    /// - Parameters:
    ///   - addresses: Up to 100 base-58 encoded account addresses. The server validates
    ///     the addresses and their count. Split larger collections into separate requests.
    ///   - commitment: The confirmation level to query. The default is `confirmed`.
    public init(addresses: [String], commitment: Commitment = .confirmed) {
        self.addresses = addresses
        self.commitment = commitment
    }

    /// Encodes the addresses, commitment, and base64 encoding as positional RPC parameters.
    ///
    /// - Parameter encoder: The encoder that receives the parameter array.
    /// - Throws: An encoding error if the encoder can't represent a parameter.
    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(addresses)
        try parameters.encode(AccountConfiguration(commitment: commitment))
    }
}
