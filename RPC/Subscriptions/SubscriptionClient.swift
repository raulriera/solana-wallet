import Foundation

/// Owns the standard Solana subscription wire protocol for interchangeable providers.
struct SubscriptionClient: Sendable {
    let endpoint: URL
    let connect: @Sendable (URL) -> any WebSocketConnection
    let redactor: any TextRedactor

    /// Opens three confirmed subscriptions and then streams their increasing change slots.
    /// - Parameter owner: The wallet's SOL address and token-account authority.
    /// - Returns: A cancellable stream after all subscription acknowledgments arrive.
    /// - Throws: A sanitized setup, timeout, or cancellation error.
    @concurrent
    func changedSlots(for owner: String) async throws -> AsyncThrowingStream<UInt64, any Error> {
        try Task.checkCancellation()
        let socket = connect(endpoint)
        do {
            let state = try await withThrowingTaskGroup(of: SubscriptionState.self) { group in
                group.addTask {
                    try await withTaskCancellationHandler {
                        try await handshake(owner: owner, socket: socket)
                    } onCancel: { socket.cancel() }
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(30))
                    throw RPCError.transport(.timedOut)
                }
                defer { group.cancelAll() }
                return try await group.next()!
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
                                    try await Task.sleep(for: .seconds(30))
                                    try await socket.ping()
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

    /// Registers SOL and both token-program filters before returning control to the consumer.
    /// - Parameters:
    ///   - owner: The wallet address to filter.
    ///   - socket: The connected transport.
    /// - Returns: Validated subscription IDs and any change observed during setup.
    /// - Throws: An encoding, transport, response, or cancellation error.
    private func handshake(owner: String, socket: any WebSocketConnection) async throws -> SubscriptionState {
        let requests = [
            SubscriptionRequest(owner: owner),
            SubscriptionRequest(owner: owner, program: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"),
            SubscriptionRequest(owner: owner, program: "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"),
        ]
        var state = SubscriptionState(pending: Dictionary(uniqueKeysWithValues: requests.map {
            ($0.id, $0.method == "accountSubscribe" ? "accountNotification" : "programNotification")
        }))
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
