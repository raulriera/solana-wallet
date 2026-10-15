import Foundation

/// The update streams of everyone waiting on one wallet, each keeping its two newest unread updates.
struct UpdateConsumers {
    private var continuations: [UUID: AsyncStream<Update>.Continuation] = [:]

    /// Whether no consumer remains.
    var isEmpty: Bool {
        continuations.isEmpty
    }

    /// Adds a consumer and returns its stream.
    /// - Parameters:
    ///   - first: An update the new consumer receives at once, such as the state the others already have.
    ///   - onEnd: Work to run with the consumer's identifier when its stream ends, such as removing it.
    /// - Returns: The consumer's stream.
    mutating func add(first: Update? = nil, onEnd: @escaping @Sendable (UUID) async -> Void) -> AsyncStream<Update> {
        let (stream, continuation) = AsyncStream<Update>.makeStream(bufferingPolicy: .bufferingNewest(2))
        let id = UUID()
        continuation.onTermination = { @Sendable _ in
            Task { @concurrent in await onEnd(id) }
        }
        if let first { continuation.yield(first) }
        continuations[id] = continuation
        return stream
    }

    /// Sends an update to every consumer.
    /// - Parameter update: The state to deliver.
    func send(_ update: Update) {
        for continuation in continuations.values { continuation.yield(update) }
    }

    /// Ends every consumer's stream.
    func finish() {
        for continuation in continuations.values { continuation.finish() }
    }

    /// Removes a consumer whose stream ended.
    /// - Parameter id: The identifier that ``add(first:onEnd:)`` passed to the consumer's end handler.
    mutating func remove(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
