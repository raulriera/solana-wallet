import Foundation

/// The update streams of one wallet's consumers, each buffering its two newest unread updates.
struct UpdateConsumers {
    private var continuations: [UUID: AsyncStream<Update>.Continuation] = [:]

    var isEmpty: Bool {
        continuations.isEmpty
    }

    /// Adds a consumer and returns its stream.
    ///
    /// - Parameters:
    ///   - first: An update the consumer receives first, or `nil`.
    ///   - onEnd: Work to run with the consumer's identifier when its stream ends.
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
    ///
    /// - Parameter update: The update to send.
    func send(_ update: Update) {
        for continuation in continuations.values { continuation.yield(update) }
    }

    /// Ends every consumer's stream.
    func finish() {
        for continuation in continuations.values { continuation.finish() }
    }

    /// Removes a consumer whose stream ended.
    ///
    /// - Parameter id: The consumer's identifier.
    mutating func remove(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
