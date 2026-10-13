/// Subscriptions that share one connection, and the events that their notifications produce.
///
/// The subscription client sends every request, waits for each acknowledgment,
/// and passes each notification to ``event(for:)`` in the order it arrives.
protocol SubscriptionGroup<Event>: Sendable {
    /// The value that the subscription stream delivers.
    associatedtype Event: Sendable

    /// The subscription requests to send on the connection, in order; read once per connection.
    var requests: [SubscriptionRequest] { get }

    /// How the stream keeps events that the consumer hasn't read yet.
    var bufferingPolicy: AsyncThrowingStream<Event, any Error>.Continuation.BufferingPolicy { get }

    /// Turns one notification into an event.
    /// - Parameter notification: A notification for one of the acknowledged requests.
    /// - Returns: The event to deliver, or `nil` when the notification adds nothing new.
    /// - Throws: A decoding error when the notification's result is malformed.
    mutating func event(for notification: SubscriptionNotification) throws -> Event?
}
