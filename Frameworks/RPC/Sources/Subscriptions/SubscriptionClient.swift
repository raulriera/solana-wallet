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

    /// Opens one confirmed subscription per account on one connection, then streams their increasing change slots.
    /// - Parameter addresses: The accounts to watch; a repeated address is watched once.
    /// - Returns: A cancellable stream after all subscription acknowledgments arrive.
    /// - Throws: A sanitized setup, timeout, or cancellation error.
    @concurrent
    func changedSlots(for addresses: [String]) async throws -> AsyncThrowingStream<UInt64, any Error> {
        try Task.checkCancellation()
        let socket = connect(endpoint)
        do {
            let state = try await withTimeout(.seconds(30)) {
                try await withTaskCancellationHandler {
                    try await handshake(addresses: addresses, socket: socket)
                } onCancel: { socket.cancel() }
            }
            try Task.checkCancellation()
            let (stream, continuation) = AsyncThrowingStream<UInt64, any Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
            if let slot = state.latestSlot { continuation.yield(slot) }
            let operation = Task { @concurrent in
                defer { socket.cancel() }
                do {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            var state = state
                            try await withTaskCancellationHandler {
                                while !Task.isCancelled {
                                    if let slot = try state.accept(await socket.receive(), redactor: redactor) {
                                        continuation.yield(slot)
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
                } catch { continuation.finish(throwing: sanitized(error)) }
            }
            continuation.onTermination = { @Sendable _ in operation.cancel(); socket.cancel() }
            return stream
        } catch {
            socket.cancel()
            throw sanitized(error)
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

    /// Registers every account before returning control to the consumer.
    /// - Parameters:
    ///   - addresses: The accounts to watch.
    ///   - socket: The connected transport.
    /// - Returns: Validated subscription IDs and any change observed during setup.
    /// - Throws: An encoding, transport, response, or cancellation error.
    private func handshake(addresses: [String], socket: any WebSocketConnection) async throws -> SubscriptionState {
        // Providers either reuse one subscription for a repeated account or notify it twice, so send each once.
        var unique = Set<String>()
        let requests = addresses.filter { unique.insert($0).inserted }.map(SubscriptionRequest.init(address:))
        var state = SubscriptionState(pending: Set(requests.map(\.id)))
        for request in requests {
            try Task.checkCancellation()
            guard let data = try? JSONEncoder().encode(request) else { throw RPCError.encoding }
            try await socket.send(data)
        }
        while !state.pending.isEmpty {
            try Task.checkCancellation()
            _ = try state.accept(await socket.receive(), redactor: redactor)
        }
        return state
    }

    /// Removes authenticated endpoints and provider text from errors before crossing the module boundary.
    /// - Parameter error: A subscription or transport failure.
    /// - Returns: Cancellation, a sanitized RPC error, or a transport code without its userInfo.
    private func sanitized(_ error: any Error) -> any Error {
        if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
            return CancellationError()
        }
        if let error = error as? RPCError {
            switch error {
            case .server(let code, let message): return RPCError.server(code: code, message: redactor.redact(message))
            case .http(let status, let retry): return RPCError.http(statusCode: status, retryAfter: retry.map(redactor.redact))
            default: return error
            }
        }
        if error is DecodingError { return RPCError.decoding }
        return RPCError.transport((error as? URLError)?.code ?? .unknown)
    }
}
