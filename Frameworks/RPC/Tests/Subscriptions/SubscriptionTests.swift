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
        _ = try await client(socket: socket).changedSlots(for: "wallet")
        await socket.waitUntilCancelled()
        #expect(socket.isCancelled)
    }

    /// Verifies both concrete providers use the standard confirmed filters and decode the same events.
    /// - Parameter helius: Whether to exercise Helius or the public Solana client.
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func `Wallet subscriptions cover SOL and both token programs at confirmed`(helius: Bool) async throws {
        let socket = SocketFixture()
        let source = client(socket: socket, helius: helius)
        let slots = try await source.changedSlots(for: "wallet")
        try #require(socket.requests.count == 3)
        let bodies = try socket.requests.map { try #require(JSONSerialization.jsonObject(with: $0) as? [String: Any]) }
        #expect(bodies.map { $0["method"] as? String } == ["accountSubscribe", "programSubscribe", "programSubscribe"])
        for (index, body) in bodies.enumerated() {
            let params = try #require(body["params"] as? [Any])
            try #require(params.count == 2)
            let options = try #require(params[1] as? [String: Any])
            #expect(options["commitment"] as? String == "confirmed")
            if index == 0 { #expect(params[0] as? String == "wallet") }
            else {
                let filters = try #require(options["filters"] as? [[String: Any]])
                let match = try #require(filters.first?["memcmp"] as? [String: Any])
                #expect(match["offset"] as? Int == 32)
                #expect(match["bytes"] as? String == "wallet")
                #expect(filters.allSatisfy { $0["dataSize"] == nil })
            }
        }
        let tokenParams = try #require(bodies[2]["params"] as? [Any])
        #expect(tokenParams[0] as? String == "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb")
        let (observed, delivered) = AsyncStream<UInt64>.makeStream()
        let task = Task { for try await slot in slots { delivered.yield(slot) } }
        defer { task.cancel(); delivered.finish() }
        var received = observed.makeAsyncIterator()
        socket.notify(slot: 10)
        #expect(await received.next() == 10)
        socket.notify(slot: 9)
        socket.notify(slot: 10)
        socket.notify(slot: 12, subscription: 3, method: "programNotification")
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
        let slots = try await client(socket: socket).changedSlots(for: "wallet")
        let task = Task {
            var iterator = slots.makeAsyncIterator()
            return try await iterator.next()
        }
        #expect(try await task.value == 99)
        socket.cancel()
    }

    /// Verifies decoder errors for another subscription stop the stream without retrying.
    @Test(.timeLimit(.minutes(1)))
    func `Unrelated subscription IDs terminate the stream`() async throws {
        let socket = SocketFixture()
        let stream = try await client(socket: socket).changedSlots(for: "wallet")
        socket.notify(slot: 7, subscription: 999)
        var iterator = stream.makeAsyncIterator()
        await #expect(throws: RPCError.invalidResponse(.mismatchedID)) { try await iterator.next() }
        #expect(socket.requests.count == 3)
        #expect(socket.isCancelled)
    }

    /// Verifies provider credentials in a null-ID server error never reach consumers.
    @Test
    func `Subscription server errors preserve codes and redact credentials`() async {
        let socket = SocketFixture { _, _ in
            [Data(#"{"jsonrpc":"2.0","id":null,"error":{"code":429,"message":"fixture-key limited"}}"#.utf8)]
        }
        await #expect(throws: RPCError.server(code: 429, message: "[redacted] limited")) {
            try await client(socket: socket).changedSlots(for: "wallet")
        }
        #expect(socket.isCancelled)
        #expect(socket.requests.count == 3)
    }

    /// Verifies a lost socket surfaces its transport code without leaking endpoint diagnostics or reconnecting.
    @Test(.timeLimit(.minutes(1)))
    func `Subscription disconnects end the stream without reconnecting`() async throws {
        let socket = SocketFixture()
        let stream = try await client(socket: socket).changedSlots(for: "wallet")
        socket.fail(URLError(.networkConnectionLost, userInfo: [NSLocalizedDescriptionKey: "fixture-key"]))
        var iterator = stream.makeAsyncIterator()
        await #expect(throws: RPCError.transport(.networkConnectionLost)) { try await iterator.next() }
        #expect(socket.isCancelled)
        #expect(socket.requests.count == 3)
    }

    /// Verifies cancellation while waiting for an acknowledgment promptly closes the socket.
    @Test(.timeLimit(.minutes(1)))
    func `Cancelling subscription setup closes its connection`() async throws {
        let socket = SocketFixture { _, _ in [] }
        let task = Task { try await client(socket: socket).changedSlots(for: "wallet") }
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
    /// - Returns: The provider-neutral subscription contract.
    private func client(socket: SocketFixture, helius: Bool = true) -> any AccountChangeProviding {
        let http = StubTransport { _ in throw URLError(.notConnectedToInternet) }
        if helius {
            return HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: http, socket: { url in
                #expect(url.scheme == "wss" && url.host() == "devnet.helius-rpc.com")
                return socket
            })
        }
        return Solana(network: .devnet, transport: http, socket: { url in
            #expect(url.scheme == "wss" && url.host() == "api.devnet.solana.com")
            return socket
        })
    }
}
