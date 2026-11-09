import Foundation
import Synchronization
import Testing
@testable import RPC

final class SocketFixture: WebSocketConnection {
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

    var subscribedAddresses: [String] {
        requests.compactMap { request in
            let body = try? JSONSerialization.jsonObject(with: request) as? [String: Any]
            return (body?["params"] as? [Any])?.first as? String
        }
    }

    func send(_ data: Data) async throws {
        try Task.checkCancellation()
        let ordinal = state.withLock { $0.requests.append(data); return $0.requests.count }
        outgoing.yield(data)
        for frame in try respond(data, ordinal) { incoming.yield(frame) }
    }

    func receive() async throws -> Data {
        var iterator = messages.makeAsyncIterator()
        guard let frame = try await iterator.next() else {
            try Task.checkCancellation()
            throw URLError(.networkConnectionLost)
        }
        return frame
    }

    func ping() async throws {
        try Task.checkCancellation()
        guard !answersPings else { return }
        let (pongs, pong) = AsyncStream<Void>.makeStream()
        for await _ in pongs {}
        pong.finish()
        throw CancellationError()
    }

    func cancel() {
        state.withLock { $0.cancelled = true }
        didClose.yield(())
        didClose.finish()
        incoming.finish()
        outgoing.finish()
    }

    func waitUntilCancelled() async {
        if isCancelled { return }
        var iterator = closure.makeAsyncIterator()
        _ = await iterator.next()
    }

    func notify(slot: UInt64, subscription: UInt64 = 1) {
        incoming.yield(Data(#"{"jsonrpc":"2.0","method":"accountNotification","params":{"subscription":\#(subscription),"result":{"context":{"slot":\#(slot)},"value":{}}}}"#.utf8))
    }

    func notifyLanding(error: String = "null", subscription: UInt64 = 1) {
        incoming.yield(Self.landingNotification(error: error, subscription: subscription))
    }

    func notify(root: UInt64, subscription: UInt64 = 2) {
        incoming.yield(Self.rootNotification(root, subscription: subscription))
    }

    func acknowledge(_ request: Data, ordinal: Int) throws {
        incoming.yield(try Self.acknowledgment(of: request, ordinal: ordinal))
    }

    static func acknowledgment(of request: Data, ordinal: Int) throws -> Data {
        let body = try #require(JSONSerialization.jsonObject(with: request) as? [String: Any])
        let id = try #require(body["id"] as? String)
        return Data(#"{"jsonrpc":"2.0","id":"\#(id)","result":\#(ordinal)}"#.utf8)
    }

    static func landingNotification(error: String = "null", subscription: UInt64 = 1) -> Data {
        Data(#"{"jsonrpc":"2.0","method":"signatureNotification","params":{"subscription":\#(subscription),"result":{"context":{"slot":5},"value":{"err":\#(error)}}}}"#.utf8)
    }

    static func rootNotification(_ root: UInt64, subscription: UInt64 = 2) -> Data {
        Data(#"{"jsonrpc":"2.0","method":"rootNotification","params":{"subscription":\#(subscription),"result":\#(root)}}"#.utf8)
    }

    static func serverError(code: Int) -> Data {
        Data(#"{"jsonrpc":"2.0","id":null,"error":{"code":\#(code),"message":"refused"}}"#.utf8)
    }

    func fail(_ error: any Error) { incoming.finish(throwing: error) }

    private struct State { var requests: [Data] = []; var cancelled = false }
}
