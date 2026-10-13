import Foundation

/// A notification for one of a connection's acknowledged subscriptions.
struct SubscriptionNotification: Sendable {
    /// The subscription request that the notification answers.
    let request: SubscriptionRequest
    /// The notification's JSON bytes.
    let data: Data

    /// Decodes the notification's result.
    /// - Parameter type: The result type of the subscription method.
    /// - Returns: The decoded result.
    /// - Throws: A decoding error when the result doesn't match the type.
    func result<Value: Decodable>(_ type: Value.Type) throws -> Value {
        try JSONDecoder().decode(Envelope<Value>.self, from: data).params.result
    }

    /// The notification fields that surround its result.
    private struct Envelope<Value: Decodable>: Decodable {
        let params: Parameters
        struct Parameters: Decodable { let result: Value }
    }
}
