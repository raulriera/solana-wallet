import Foundation
import Testing
@testable import RPC

/// Verifies provider-owned subscriptions with controlled WebSocket frames.
struct SubscriptionTests {
    /// Verifies an abandoned stream releases its reader and keep-alive task without explicit cancellation.
    @Test(.timeLimit(.minutes(1)))
    func `Discarding an unconsumed subscription closes its connection`() async throws {
        let socket = SocketFixture()
        defer { socket.cancel() }
        _ = try await client(socket: socket).changedSlots(for: ["wallet"])
        await socket.waitUntilCancelled()
        #expect(socket.isCancelled)
    }

    /// Verifies both concrete providers watch each account once at confirmed and decode the same events.
    /// - Parameter helius: Whether to exercise Helius or the public Solana client.
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func `Each account gets one confirmed subscription`(helius: Bool) async throws {
        let socket = SocketFixture()
        let source = client(socket: socket, helius: helius)
        let slots = try await source.changedSlots(for: ["wallet", "token-account", "wallet"])
        #expect(socket.subscribedAddresses == ["wallet", "token-account"])
        for request in socket.requests {
            let body = try #require(JSONSerialization.jsonObject(with: request) as? [String: Any])
            #expect(body["method"] as? String == "accountSubscribe")
            let params = try #require(body["params"] as? [Any])
            try #require(params.count == 2)
            let options = try #require(params[1] as? [String: Any])
            #expect(options["commitment"] as? String == "confirmed")
            #expect(options["encoding"] as? String == "base64")
        }
        let (observed, delivered) = AsyncStream<UInt64>.makeStream()
        let task = Task { for try await slot in slots { delivered.yield(slot) } }
        defer { task.cancel(); delivered.finish() }
        var received = observed.makeAsyncIterator()
        socket.notify(slot: 10)
        #expect(await received.next() == 10)
        socket.notify(slot: 9)
        socket.notify(slot: 10)
        socket.notify(slot: 12, subscription: 2)
        #expect(await received.next() == 12)
        task.cancel()
        _ = try? await task.value
        #expect(socket.isCancelled)
    }

    /// Verifies account notifications received before all acknowledgments aren't lost.
    @Test(.timeLimit(.minutes(1)))
    func `Subscription setup retains early notifications`() async throws {
        let socket = SocketFixture { data, ordinal in
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let id = try #require(body["id"] as? String)
            var frames = [Data(#"{"jsonrpc":"2.0","id":"\#(id)","result":\#(ordinal)}"#.utf8)]
            if ordinal == 1 {
                frames.append(Data(#"{"jsonrpc":"2.0","method":"accountNotification","params":{"subscription":1,"result":{"context":{"slot":99},"value":{}}}}"#.utf8))
            }
            return frames
        }
        defer { socket.cancel() }
        let slots = try await client(socket: socket).changedSlots(for: ["wallet"])
        var iterator = slots.makeAsyncIterator()
        #expect(try await iterator.next() == 99)
    }

    /// Verifies decoder errors for another subscription stop the stream without retrying.
    @Test(.timeLimit(.minutes(1)))
    func `Unrelated subscription IDs terminate the stream`() async throws {
        let socket = SocketFixture()
        let stream = try await client(socket: socket).changedSlots(for: ["wallet"])
        socket.notify(slot: 7, subscription: 999)
        var iterator = stream.makeAsyncIterator()
        await #expect(throws: RPCError.invalidResponse(.mismatchedID)) { try await iterator.next() }
        #expect(socket.requests.count == 1)
        #expect(socket.isCancelled)
    }

    /// Verifies a notification for an acknowledged subscription stops the stream when its method or result doesn't match.
    /// - Parameters:
    ///   - frame: An account-shaped notification with another subscription method, or an account notification without a slot.
    ///   - error: The error that ends the stream.
    @Test(.timeLimit(.minutes(1)), arguments: [
        (#"{"jsonrpc":"2.0","method":"rootNotification","params":{"subscription":1,"result":{"context":{"slot":5},"value":{}}}}"#,
         RPCError.invalidResponse(.mismatchedID)),
        (#"{"jsonrpc":"2.0","method":"accountNotification","params":{"subscription":1,"result":{"context":{},"value":{}}}}"#,
         .decoding),
    ])
    func `Notifications with another method or without a slot terminate the stream`(frame: String, error: RPCError) async throws {
        let socket = SocketFixture { data, ordinal in
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let id = try #require(body["id"] as? String)
            return [Data(#"{"jsonrpc":"2.0","id":"\#(id)","result":\#(ordinal)}"#.utf8), Data(frame.utf8)]
        }
        let stream = try await client(socket: socket).changedSlots(for: ["wallet"])
        var iterator = stream.makeAsyncIterator()
        await #expect(throws: error) { try await iterator.next() }
        #expect(socket.requests.count == 1)
        #expect(socket.isCancelled)
    }

    /// Verifies an acknowledgment for a request that wasn't sent fails setup and closes the connection.
    @Test
    func `Acknowledgments for unsent requests fail subscription setup`() async {
        let socket = SocketFixture { _, _ in [Data(#"{"jsonrpc":"2.0","id":"another-request","result":1}"#.utf8)] }
        await #expect(throws: RPCError.invalidResponse(.mismatchedID)) {
            try await client(socket: socket).changedSlots(for: ["wallet"])
        }
        #expect(socket.isCancelled)
    }

    /// Verifies two requests acknowledged with the same subscription number fail setup and close the connection.
    @Test
    func `Subscription numbers acknowledged twice fail subscription setup`() async {
        let socket = SocketFixture { data, _ in
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let id = try #require(body["id"] as? String)
            return [Data(#"{"jsonrpc":"2.0","id":"\#(id)","result":1}"#.utf8)]
        }
        await #expect(throws: RPCError.invalidResponse(.mismatchedID)) {
            try await client(socket: socket).changedSlots(for: ["wallet", "token-account"])
        }
        #expect(socket.requests.count == 2)
        #expect(socket.isCancelled)
    }

    /// Verifies provider credentials in a null-ID server error never reach consumers.
    @Test
    func `Subscription server errors preserve codes and redact credentials`() async {
        let socket = SocketFixture { _, _ in
            [Data(#"{"jsonrpc":"2.0","id":null,"error":{"code":429,"message":"fixture-key limited"}}"#.utf8)]
        }
        await #expect(throws: RPCError.server(code: 429, message: "[redacted] limited")) {
            try await client(socket: socket).changedSlots(for: ["wallet"])
        }
        #expect(socket.isCancelled)
        #expect(socket.requests.count == 1)
    }

    /// Verifies a lost socket surfaces its transport code without leaking endpoint diagnostics or reconnecting.
    @Test(.timeLimit(.minutes(1)))
    func `Subscription disconnects end the stream without reconnecting`() async throws {
        let socket = SocketFixture()
        let stream = try await client(socket: socket).changedSlots(for: ["wallet"])
        socket.fail(URLError(.networkConnectionLost, userInfo: [NSLocalizedDescriptionKey: "fixture-key"]))
        var iterator = stream.makeAsyncIterator()
        await #expect(throws: RPCError.transport(.networkConnectionLost)) { try await iterator.next() }
        #expect(socket.isCancelled)
        #expect(socket.requests.count == 1)
    }

    /// Verifies a keep-alive ping without a pong ends the stream as a lost connection instead of waiting forever.
    @Test(.timeLimit(.minutes(1)))
    func `A ping without a pong ends the stream with a timeout`() async throws {
        let socket = SocketFixture(answersPings: false)
        let subscriptions = SubscriptionClient(endpoint: URL(string: "wss://fixture.invalid")!, connect: { _ in socket },
                                               redactor: SecretRedactor(secrets: []),
                                               pingInterval: .milliseconds(10), pongTimeout: .milliseconds(10))
        let stream = try await subscriptions.changedSlots(for: ["wallet"])
        var iterator = stream.makeAsyncIterator()
        await #expect(throws: RPCError.transport(.timedOut)) { try await iterator.next() }
        #expect(socket.isCancelled)
    }

    /// Verifies cancellation while waiting for an acknowledgment promptly closes the socket.
    @Test(.timeLimit(.minutes(1)))
    func `Cancelling subscription setup closes its connection`() async throws {
        let socket = SocketFixture { _, _ in [] }
        let task = Task { try await client(socket: socket).changedSlots(for: ["wallet"]) }
        defer { task.cancel() }
        var sent = socket.sent.makeAsyncIterator()
        _ = try #require(await sent.next())
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(socket.isCancelled)
    }

    /// Creates the actual provider with fixtures only at its transport boundaries.
    /// - Parameters:
    ///   - socket: The scripted WebSocket connection.
    ///   - helius: Whether to use Helius or the public Solana client.
    ///   - connected: Runs each time the provider opens a WebSocket connection.
    /// - Returns: The provider-neutral subscription contracts.
    func client(socket: SocketFixture, helius: Bool = true,
                connected: @escaping @Sendable () -> Void = {}) -> any AccountChangeProviding & SignatureEventProviding {
        let http = StubTransport { _ in throw URLError(.notConnectedToInternet) }
        if helius {
            return HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: http, socket: { url in
                #expect(url.scheme == "wss" && url.host() == "devnet.helius-rpc.com")
                connected()
                return socket
            })
        }
        return Solana(network: .devnet, transport: http, socket: { url in
            #expect(url.scheme == "wss" && url.host() == "api.devnet.solana.com")
            connected()
            return socket
        })
    }
}
