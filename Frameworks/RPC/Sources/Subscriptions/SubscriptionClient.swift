import Foundation
import Redaction

/// A client that opens standard Solana subscriptions over a WebSocket connection.
struct SubscriptionClient: Sendable, Redacted {
    let endpoint: URL
    let connect: @Sendable (URL) -> any WebSocketConnection
    let redactor: any TextRedactor
    /// The clock that times setup, pings, and pongs.
    var clock: any Clock<Duration> = ContinuousClock()

    private static let setupTimeout = Duration.seconds(30)
    private static let pingInterval = Duration.seconds(30)
    private static let pongTimeout = Duration.seconds(10)

    /// Opens one finalized subscription per account on one connection and streams their increasing change slots.
    ///
    /// - Parameter addresses: The accounts to watch.
    /// - Returns: A stream of change slots.
    /// - Throws: An ``RPCError`` or `CancellationError`.
    func changedSlots(for addresses: [String]) async throws -> AsyncThrowingStream<UInt64, any Error> {
        try await events(for: .accountChanges(for: addresses))
    }

    /// Subscribes to a signature and to new roots on one connection and streams their events.
    ///
    /// - Parameter signature: The base-58 encoded signature of a sent transaction.
    /// - Returns: A stream of signature events.
    /// - Throws: An ``RPCError`` or `CancellationError`.
    func events(for signature: String) async throws -> AsyncThrowingStream<SignatureEvent, any Error> {
        try await events(for: .signatureWatch(for: signature))
    }

    /// Opens a group's subscriptions on one connection and streams the events of their notifications.
    ///
    /// - Parameter subscriptions: The subscriptions to open.
    /// - Returns: A stream of the group's events.
    /// - Throws: An ``RPCError`` or `CancellationError`.
    @concurrent
    func events<Group: SubscriptionGroup>(for subscriptions: Group) async throws
        -> AsyncThrowingStream<Group.Event, any Error> {
        try Task.checkCancellation()
        let socket = connect(endpoint)
        do {
            let (state, setupEvents) = try await withTimeout(Self.setupTimeout, clock: clock) {
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
                                    try await clock.sleep(for: Self.pingInterval)
                                    try await withTimeout(Self.pongTimeout, clock: clock) { try await socket.ping() }
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

    /// Sends every subscription request and waits for each acknowledgment.
    ///
    /// - Parameters:
    ///   - subscriptions: The subscriptions to open.
    ///   - socket: The connection.
    /// - Returns: The acknowledged state and the events received during setup.
    /// - Throws: An ``RPCError``, a transport error, or `CancellationError`.
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
