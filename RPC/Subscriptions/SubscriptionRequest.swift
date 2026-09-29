import Foundation

/// The private wire request for one standard Solana subscription.
struct SubscriptionRequest: Encodable {
    let jsonrpc = "2.0"
    let id = UUID().uuidString
    let method: String
    let params: Parameters

    /// Creates a confirmed SOL or wallet-filtered token-program subscription.
    /// - Parameters:
    ///   - owner: The wallet address whose balances may change.
    ///   - program: The token program, or `nil` to watch the wallet's SOL account.
    init(owner: String, program: String? = nil) {
        method = program == nil ? "accountSubscribe" : "programSubscribe"
        params = Parameters(address: program ?? owner, owner: program == nil ? nil : owner)
    }

    /// Encodes the heterogeneous positional subscription parameters.
    struct Parameters: Encodable {
        let address: String
        let owner: String?

        /// Encodes the address and confirmed commitment with an optional token authority filter.
        /// - Parameter encoder: The outgoing JSON encoder.
        /// - Throws: An encoding error.
        func encode(to encoder: any Encoder) throws {
            var values = encoder.unkeyedContainer()
            try values.encode(address)
            try values.encode(Configuration(filters: owner.map { [Filter(memcmp: Match(bytes: $0))] }))
        }
    }

    /// Requests parsed data while allowing variable-sized Token-2022 accounts.
    private struct Configuration: Encodable {
        let commitment = "confirmed"
        let encoding = "jsonParsed"
        let filters: [Filter]?
    }
    /// Matches the token authority in the common base account layout.
    private struct Filter: Encodable { let memcmp: Match }
    /// Avoids a data-size filter that would exclude Token-2022 extensions.
    private struct Match: Encodable { let offset = 32; let bytes: String }
}
