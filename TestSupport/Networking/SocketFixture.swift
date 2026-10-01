import Foundation
import Synchronization
import Testing
@testable import RPC

/// Supplies WebSocket frames at the transport boundary without replacing a provider client.
final class SocketFixture: WebSocketConnection {
    /// Produces response frames for an outgoing message and its one-based ordinal.
    typealias Responder = @Sendable (Data, Int) throws -> [Data]

    private let messages: AsyncThrowingStream<Data, any Error>
    private let incoming: AsyncThrowingStream<Data, any Error>.Continuation
    let sent: AsyncStream<Data>
    private let outgoing: AsyncStream<Data>.Continuation
    private let closure: AsyncStream<Void>
    private let didClose: AsyncStream<Void>.Continuation
    private let state = Mutex(State())
    private let respond: Responder

    /// Creates a connection with automatic or scripted subscription responses.
    /// - Parameter respond: The response frames for an outgoing message and its ordinal.
    init(respond: @escaping Responder = { data, ordinal in
        let request = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let id = try #require(request["id"] as? String)
        return [Data(#"{"jsonrpc":"2.0","id":"\#(id)","result":\#(ordinal)}"#.utf8)]
    }) {
        (messages, incoming) = AsyncThrowingStream.makeStream()
        (sent, outgoing) = AsyncStream.makeStream()
        (closure, didClose) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.respond = respond
    }

    var requests: [Data] { state.withLock { $0.requests } }
    var isCancelled: Bool { state.withLock { $0.cancelled } }

    /// Records an outgoing request and enqueues its scripted replies.
    /// - Parameter data: The request encoded by the real provider.
    /// - Throws: A fixture or cancellation error.
    func send(_ data: Data) async throws {
        try Task.checkCancellation()
        let ordinal = state.withLock { $0.requests.append(data); return $0.requests.count }
        outgoing.yield(data)
        for frame in try respond(data, ordinal) { incoming.yield(frame) }
    }

    /// Waits for the next frame, preserving cancellation of the real client's read loop.
    /// - Returns: One scripted server message.
    /// - Throws: A scripted, cancellation, or connection-closed error.
    func receive() async throws -> Data {
        var iterator = messages.makeAsyncIterator()
        guard let frame = try await iterator.next() else {
            try Task.checkCancellation()
            throw URLError(.networkConnectionLost)
        }
        return frame
    }

    /// Provides a successful keep-alive operation for the fixture connection.
    /// - Throws: A cancellation error when the read operation has ended.
    func ping() async throws { try Task.checkCancellation() }

    /// Releases waiting receive calls and records transport cancellation.
    func cancel() {
        state.withLock { $0.cancelled = true }
        didClose.yield(())
        didClose.finish()
        incoming.finish()
        outgoing.finish()
    }

    /// Waits for transport cleanup without relying on scheduler delays.
    func waitUntilCancelled() async {
        if isCancelled { return }
        var iterator = closure.makeAsyncIterator()
        _ = await iterator.next()
    }

    /// Delivers a confirmed-change notification through the real protocol decoder.
    /// - Parameters:
    ///   - slot: The notification's context slot.
    ///   - subscription: The acknowledged server subscription ID.
    ///   - method: The corresponding notification method.
    func notify(slot: UInt64, subscription: UInt64 = 1, method: String = "accountNotification") {
        incoming.yield(Data(#"{"jsonrpc":"2.0","method":"\#(method)","params":{"subscription":\#(subscription),"result":{"context":{"slot":\#(slot)},"value":{}}}}"#.utf8))
    }

    /// Ends the transport with a scripted network failure.
    /// - Parameter error: The error delivered to the client's reader.
    func fail(_ error: any Error) { incoming.finish(throwing: error) }

    /// Protects synchronous request inspection and cancellation flags.
    private struct State { var requests: [Data] = []; var cancelled = false }
}
