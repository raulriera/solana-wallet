import Foundation

/// A notification for one of a connection's acknowledged subscriptions.
struct SubscriptionNotification: Sendable {
    let request: SubscriptionRequest
    /// The notification's JSON bytes.
    let data: Data

    /// Decodes the notification's result.
    ///
    /// - Parameter type: The result type of the subscription method.
    /// - Returns: The decoded result.
    /// - Throws: A decoding error.
    func result<Value: Decodable>(_ type: Value.Type) throws -> Value {
        try JSONDecoder().decode(Envelope<Value>.self, from: data).params.result
    }

    /// The notification fields that surround its result.
    private struct Envelope<Value: Decodable>: Decodable {
        let params: Parameters
        /// The notification parameters that hold its result.
        struct Parameters: Decodable { let result: Value }
    }
}
