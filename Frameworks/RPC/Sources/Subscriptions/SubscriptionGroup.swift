/// Subscriptions that share one connection, and the events that their notifications produce.
protocol SubscriptionGroup<Event>: Sendable {
    /// The value that the subscription stream delivers.
    associatedtype Event: Sendable

    /// The subscription requests to send on the connection, in order.
    var requests: [SubscriptionRequest] { get }

    var bufferingPolicy: AsyncThrowingStream<Event, any Error>.Continuation.BufferingPolicy { get }

    /// Turns one notification into an event.
    ///
    /// - Parameter notification: A notification for one of the acknowledged requests.
    /// - Returns: The event to deliver, or `nil` when the notification adds nothing new.
    /// - Throws: A decoding error.
    mutating func event(for notification: SubscriptionNotification) throws -> Event?
}
