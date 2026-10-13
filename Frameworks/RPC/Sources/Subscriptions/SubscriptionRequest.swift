import Foundation

/// The private wire request for one standard Solana subscription.
struct SubscriptionRequest: Encodable, Sendable {
    let jsonrpc = "2.0"
    let id = UUID().uuidString
    /// The subscription method, such as `accountSubscribe`.
    let method: String
    private let params: Parameters
    /// The method of the notifications that the subscription receives, such as `accountNotification`.
    let notification: String

    /// Creates a request for one subscription.
    /// - Parameters:
    ///   - method: The subscription method, such as `accountSubscribe`.
    ///   - params: The positional parameters, in order.
    ///   - notification: The method of the notifications that the subscription receives.
    init(method: String, params: [any Encodable & Sendable], notification: String) {
        self.method = method
        self.params = Parameters(values: params)
        self.notification = notification
    }

    /// The fields sent to the server; the notification method stays local.
    private enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params
    }

    /// Encodes heterogeneous values as positional parameters.
    private struct Parameters: Encodable, Sendable {
        let values: [any Encodable & Sendable]

        /// Encodes each value in order.
        /// - Parameter encoder: The outgoing JSON encoder.
        /// - Throws: An encoding error.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            for value in values { try container.encode(value) }
        }
    }
}
