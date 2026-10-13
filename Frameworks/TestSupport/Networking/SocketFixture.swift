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
    private let answersPings: Bool

    /// Creates a connection with automatic or scripted subscription responses.
    /// - Parameters:
    ///   - answersPings: Whether each keep-alive ping gets its pong; without one, a ping waits until cancelled.
    ///   - respond: The response frames for an outgoing message and its ordinal.
    init(answersPings: Bool = true, respond: @escaping Responder = { data, ordinal in
        [try SocketFixture.acknowledgment(of: data, ordinal: ordinal)]
    }) {
        (messages, incoming) = AsyncThrowingStream.makeStream()
        (sent, outgoing) = AsyncStream.makeStream()
        (closure, didClose) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.answersPings = answersPings
        self.respond = respond
    }

    var requests: [Data] { state.withLock(\.requests) }
    var isCancelled: Bool { state.withLock(\.cancelled) }

    /// The account each sent subscription request watches, in the order they were sent.
    var subscribedAddresses: [String] {
        requests.compactMap { request in
            let body = try? JSONSerialization.jsonObject(with: request) as? [String: Any]
            return (body?["params"] as? [Any])?.first as? String
        }
    }

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

    /// Answers a keep-alive ping at once, or never when the server doesn't answer pings.
    /// - Throws: A cancellation error when the read operation has ended or the client stops waiting.
    func ping() async throws {
        try Task.checkCancellation()
        guard !answersPings else { return }
        // The pong never arrives, so only cancellation ends the wait.
        try await Task.sleep(for: .seconds(3_600))
    }

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

    /// Delivers a finalized account-change notification through the real protocol decoder.
    /// - Parameters:
    ///   - slot: The notification's context slot.
    ///   - subscription: The acknowledged server subscription ID.
    func notify(slot: UInt64, subscription: UInt64 = 1) {
        incoming.yield(Data(#"{"jsonrpc":"2.0","method":"accountNotification","params":{"subscription":\#(subscription),"result":{"context":{"slot":\#(slot)},"value":{}}}}"#.utf8))
    }

    /// Delivers a finalized signature notification through the real protocol decoder.
    /// - Parameters:
    ///   - error: The JSON of the transaction's execution error; `null` reports success.
    ///   - subscription: The acknowledged server subscription ID.
    func notifyLanding(error: String = "null", subscription: UInt64 = 1) {
        incoming.yield(Self.landingNotification(error: error, subscription: subscription))
    }

    /// Delivers a new root notification through the real protocol decoder.
    /// - Parameters:
    ///   - root: The root slot.
    ///   - subscription: The acknowledged server subscription ID.
    func notify(root: UInt64, subscription: UInt64 = 2) {
        incoming.yield(Self.rootNotification(root, subscription: subscription))
    }

    /// Acknowledges a subscription request with its ordinal as the subscription ID.
    /// - Parameters:
    ///   - request: The request encoded by the real provider.
    ///   - ordinal: The request's one-based position on the connection.
    /// - Returns: The acknowledgment frame.
    /// - Throws: A fixture error when the request has no ID.
    static func acknowledgment(of request: Data, ordinal: Int) throws -> Data {
        let body = try #require(JSONSerialization.jsonObject(with: request) as? [String: Any])
        let id = try #require(body["id"] as? String)
        return Data(#"{"jsonrpc":"2.0","id":"\#(id)","result":\#(ordinal)}"#.utf8)
    }

    /// Creates a finalized signature notification frame.
    /// - Parameters:
    ///   - error: The JSON of the transaction's execution error; `null` reports success.
    ///   - subscription: The acknowledged server subscription ID.
    /// - Returns: One WebSocket frame.
    static func landingNotification(error: String = "null", subscription: UInt64 = 1) -> Data {
        Data(#"{"jsonrpc":"2.0","method":"signatureNotification","params":{"subscription":\#(subscription),"result":{"context":{"slot":5},"value":{"err":\#(error)}}}}"#.utf8)
    }

    /// Creates a new root notification frame.
    /// - Parameters:
    ///   - root: The root slot.
    ///   - subscription: The acknowledged server subscription ID.
    /// - Returns: One WebSocket frame.
    static func rootNotification(_ root: UInt64, subscription: UInt64 = 2) -> Data {
        Data(#"{"jsonrpc":"2.0","method":"rootNotification","params":{"subscription":\#(subscription),"result":\#(root)}}"#.utf8)
    }

    /// Creates a JSON-RPC error without a request ID, which refuses a subscription or ends its stream.
    /// - Parameter code: The error code.
    /// - Returns: One WebSocket frame.
    static func serverError(code: Int) -> Data {
        Data(#"{"jsonrpc":"2.0","id":null,"error":{"code":\#(code),"message":"refused"}}"#.utf8)
    }

    /// Ends the transport with a scripted network failure.
    /// - Parameter error: The error delivered to the client's reader.
    func fail(_ error: any Error) { incoming.finish(throwing: error) }

    /// Protects synchronous request inspection and cancellation flags.
    private struct State { var requests: [Data] = []; var cancelled = false }
}
