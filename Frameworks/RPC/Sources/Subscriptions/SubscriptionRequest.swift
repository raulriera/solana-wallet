import Foundation

/// The private wire request for one standard Solana account subscription.
struct SubscriptionRequest: Encodable {
    let jsonrpc = "2.0"
    let id = UUID().uuidString
    let method = "accountSubscribe"
    let params: Parameters

    /// Creates a confirmed subscription to one account.
    /// - Parameter address: The account whose lamports or data may change.
    init(address: String) {
        params = Parameters(address: address)
    }

    /// Encodes the heterogeneous positional subscription parameters.
    struct Parameters: Encodable {
        let address: String

        /// Encodes the address and its confirmed configuration.
        /// - Parameter encoder: The outgoing JSON encoder.
        /// - Throws: An encoding error.
        func encode(to encoder: any Encoder) throws {
            var values = encoder.unkeyedContainer()
            try values.encode(address)
            try values.encode(Configuration())
        }
    }

    /// Requests compact account bytes, since notifications only signal a change.
    private struct Configuration: Encodable {
        let commitment = "confirmed"
        let encoding = "base64"
    }
}
