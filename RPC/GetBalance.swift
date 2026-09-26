/// A request for an account's native SOL balance in lamports.
public struct GetBalance: RPCRequest {
    /// The JSON-RPC method name for retrieving an account balance.
    public static let method = "getBalance"

    /// An account balance and the context in which it was read.
    public struct Response: Decodable, Sendable {
        /// The ledger context associated with the returned balance.
        public let context: Context

        /// The account balance in lamports, where one SOL equals one billion lamports.
        public let value: UInt64

        /// Creates an account balance with its ledger context.
        ///
        /// - Parameters:
        ///   - context: The ledger context associated with the balance.
        ///   - value: The account balance in lamports.
        public init(context: Context, value: UInt64) {
            self.context = context
            self.value = value
        }
    }

    /// The base-58 encoded account address to query.
    public let address: String

    /// The confirmation level requested for the account state.
    public let commitment: Commitment

    /// Creates a request for an account's native SOL balance.
    ///
    /// - Parameters:
    ///   - address: The base-58 encoded account address. The server validates this value.
    ///   - commitment: The confirmation level to query. The default is `confirmed`.
    public init(address: String, commitment: Commitment = .confirmed) {
        self.address = address
        self.commitment = commitment
    }

    /// Encodes the account address and commitment as positional RPC parameters.
    ///
    /// - Parameter encoder: The encoder that receives the parameter array.
    /// - Throws: An encoding error if the encoder can't represent a parameter.
    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(address)
        try parameters.encode(Configuration(commitment: commitment))
    }

    /// The configuration object following the address in the parameter array.
    private struct Configuration: Encodable {
        let commitment: Commitment
    }
}
