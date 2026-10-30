import Foundation

/// The JSON-RPC request for one Solana subscription.
struct SubscriptionRequest: Encodable, Sendable {
    let jsonrpc = "2.0"
    let id = UUID().uuidString
    /// The subscription method, such as `accountSubscribe`.
    let method: String
    private let params: Parameters
    /// The method of the subscription's notifications, such as `accountNotification`.
    let notification: String

    /// Creates a request for one subscription.
    ///
    /// - Parameters:
    ///   - method: The subscription method, such as `accountSubscribe`.
    ///   - params: The positional parameters, in order.
    ///   - notification: The method of the subscription's notifications.
    init(method: String, params: [any Encodable & Sendable], notification: String) {
        self.method = method
        self.params = Parameters(values: params)
        self.notification = notification
    }

    /// The fields sent to the server.
    private enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params
    }

    /// The positional parameters of a request, encoded in order.
    private struct Parameters: Encodable, Sendable {
        let values: [any Encodable & Sendable]

        func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            for value in values { try container.encode(value) }
        }
    }
}
