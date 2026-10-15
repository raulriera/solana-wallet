import Foundation

/// Owns the standard Solana subscription wire protocol for interchangeable providers.
struct SubscriptionClient: Sendable {
    let endpoint: URL
    let connect: @Sendable (URL) -> any WebSocketConnection
    let redactor: any TextRedactor
    /// How long the connection waits between keep-alive pings.
    var pingInterval: Duration = .seconds(30)
    /// How long each keep-alive ping waits for its pong before the connection counts as lost.
    var pongTimeout: Duration = .seconds(10)

    /// Opens one finalized subscription per account on one connection, then streams their increasing change slots.
    /// - Parameter addresses: The accounts to watch; a repeated address is watched once.
    /// - Returns: A cancellable stream after all subscription acknowledgments arrive.
    /// - Throws: A sanitized setup, timeout, or cancellation error.
    func changedSlots(for addresses: [String]) async throws -> AsyncThrowingStream<UInt64, any Error> {
        try await events(for: .accountChanges(for: addresses))
    }

    /// Subscribes to a signature at finalized commitment and to new roots on one connection, then streams their events.
    /// - Parameter signature: The base-58 encoded signature of a sent transaction.
    /// - Returns: A cancellable stream after both subscription acknowledgments arrive.
    /// - Throws: A sanitized setup, timeout, or cancellation error.
    func events(for signature: String) async throws -> AsyncThrowingStream<SignatureEvent, any Error> {
        try await events(for: .signatureWatch(for: signature))
    }

    /// Opens a group's subscriptions on one connection, then streams the events that their notifications produce.
    /// - Parameter subscriptions: The subscriptions to open and the decoding of their notifications.
    /// - Returns: A cancellable stream after all subscription acknowledgments arrive,
    ///   starting with the setup events that the group's buffering policy keeps.
    /// - Throws: A sanitized setup, timeout, or cancellation error.
    @concurrent
    func events<Group: SubscriptionGroup>(for subscriptions: Group) async throws
        -> AsyncThrowingStream<Group.Event, any Error> {
        try Task.checkCancellation()
        let socket = connect(endpoint)
        do {
            let (state, setupEvents) = try await withTimeout(.seconds(30)) {
                try await withTaskCancellationHandler {
                    try await handshake(subscriptions, socket: socket)
                } onCancel: { socket.cancel() }
            }
            try Task.checkCancellation()
            let (stream, continuation) = AsyncThrowingStream<Group.Event, any Error>.makeStream(
                bufferingPolicy: subscriptions.bufferingPolicy)
            for event in setupEvents { continuation.yield(event) }
            let operation = Task { @concurrent in
                defer { socket.cancel() }
                do {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            var state = state
                            try await withTaskCancellationHandler {
                                while !Task.isCancelled {
                                    if let event = try state.accept(await socket.receive(), redactor: redactor) {
                                        continuation.yield(event)
                                    }
                                }
                            } onCancel: { socket.cancel() }
                        }
                        group.addTask {
                            try await withTaskCancellationHandler {
                                while !Task.isCancelled {
                                    try await Task.sleep(for: pingInterval)
                                    try await withTimeout(pongTimeout) { try await socket.ping() }
                                }
                            } onCancel: { socket.cancel() }
                        }
                        defer { group.cancelAll() }
                        try await group.next()
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: RPCError.sanitized(error, redactor: redactor)) }
            }
            continuation.onTermination = { @Sendable _ in operation.cancel(); socket.cancel() }
            return stream
        } catch {
            socket.cancel()
            throw RPCError.sanitized(error, redactor: redactor)
        }
    }

    /// Runs an operation that must finish within a time limit.
    /// - Parameters:
    ///   - limit: The longest the operation may take.
    ///   - operation: The work, which must stop when its task is cancelled.
    /// - Returns: The operation's result.
    /// - Throws: A transport timeout when the limit passes first, or the operation's error.
    private func withTimeout<Value: Sendable>(_ limit: Duration,
                                              _ operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: limit)
                throw RPCError.transport(.timedOut)
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    /// Registers every subscription before returning control to the consumer.
    /// - Parameters:
    ///   - subscriptions: The subscriptions to open.
    ///   - socket: The connected transport.
    /// - Returns: The acknowledged subscriptions and the events from notifications received during setup.
    /// - Throws: An encoding, transport, response, or cancellation error.
    private func handshake<Group: SubscriptionGroup>(_ subscriptions: Group, socket: any WebSocketConnection) async throws
        -> (state: SubscriptionState<Group>, events: [Group.Event]) {
        var state = SubscriptionState(group: subscriptions)
        for request in state.requests {
            try Task.checkCancellation()
            guard let data = try? JSONEncoder().encode(request) else { throw RPCError.encoding }
            try await socket.send(data)
        }
        var events: [Group.Event] = []
        while !state.isAcknowledged {
            try Task.checkCancellation()
            if let event = try state.accept(await socket.receive(), redactor: redactor) { events.append(event) }
        }
        return (state, events)
    }
}
