import Foundation
import RPC
import Synchronization
import Testing

extension SubscriptionTests {
    @Test(.timeLimit(.minutes(1)))
    func `A signature and new roots share one connection`() async throws {
        let socket = SocketFixture()
        let connections = Mutex(0)
        defer { socket.cancel() }
        _ = try await client(socket: socket) { connections.withLock { $0 += 1 } }
            .events(for: "fixture-signature")
        #expect(connections.withLock(\.self) == 1)
        try #require(socket.requests.count == 2)
        let signature = try #require(JSONSerialization.jsonObject(with: socket.requests[0]) as? [String: Any])
        #expect(signature["method"] as? String == "signatureSubscribe")
        let params = try #require(signature["params"] as? [Any])
        try #require(params.count == 2)
        #expect(params[0] as? String == "fixture-signature")
        #expect(params[1] as? [String: String] == ["commitment": "finalized"])
        let roots = try #require(JSONSerialization.jsonObject(with: socket.requests[1]) as? [String: Any])
        #expect(roots["method"] as? String == "rootSubscribe")
        #expect((roots["params"] as? [Any])?.isEmpty == true)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [
        ("null", TransactionError?.none),
        (#"{"InstructionError":[0,{"Custom":1}]}"#,
         TransactionError(name: "InstructionError", details: .array([.integer(0), .object(["Custom": .integer(1)])]))),
    ])
    func `Landings report the transaction's execution error`(error: String, expected: TransactionError?) async throws {
        let socket = SocketFixture()
        defer { socket.cancel() }
        let events = try await client(socket: socket).events(for: "fixture-signature")
        socket.notifyLanding(error: error)
        var iterator = events.makeAsyncIterator()
        #expect(try await iterator.next() == .landed(slot: 5, error: expected))
    }

    @Test(.timeLimit(.minutes(1)))
    func `Roots only increase`() async throws {
        let socket = SocketFixture()
        defer { socket.cancel() }
        let events = try await client(socket: socket).events(for: "fixture-signature")
        var iterator = events.makeAsyncIterator()
        socket.notify(root: 10)
        #expect(try await iterator.next() == .rooted(10))
        socket.notify(root: 9)
        socket.notify(root: 10)
        socket.notify(root: 12)
        #expect(try await iterator.next() == .rooted(12))
    }

    @Test(.timeLimit(.minutes(1)))
    func `A landing during setup stays ahead of later roots`() async throws {
        let socket = SocketFixture { data, ordinal in
            let acknowledgment = try SocketFixture.acknowledgment(of: data, ordinal: ordinal)
            return ordinal == 1 ? [acknowledgment, SocketFixture.landingNotification()] : [acknowledgment]
        }
        let events = try await client(socket: socket).events(for: "fixture-signature")
        socket.notify(root: 10)
        socket.notify(root: 12)
        socket.fail(URLError(.networkConnectionLost))
        await socket.waitUntilCancelled()
        var iterator = events.makeAsyncIterator()
        #expect(try await iterator.next() == .landed(slot: 5, error: nil))
        #expect(try await iterator.next() == .rooted(10))
        #expect(try await iterator.next() == .rooted(12))
        await #expect(throws: RPCError.transport(.networkConnectionLost)) { try await iterator.next() }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [
        #"{"jsonrpc":"2.0","method":"signatureNotification","params":{"subscription":1,"result":{"context":{"slot":5},"value":{}}}}"#,
        #"{"jsonrpc":"2.0","method":"rootNotification","params":{"subscription":2,"result":{"slot":5}}}"#,
    ])
    func `Malformed landings and roots terminate the stream`(frame: String) async throws {
        let socket = SocketFixture { data, ordinal in
            let acknowledgment = try SocketFixture.acknowledgment(of: data, ordinal: ordinal)
            return ordinal == 2 ? [acknowledgment, Data(frame.utf8)] : [acknowledgment]
        }
        let events = try await client(socket: socket).events(for: "fixture-signature")
        var iterator = events.makeAsyncIterator()
        await #expect(throws: RPCError.decoding) { try await iterator.next() }
        #expect(socket.isCancelled)
    }

    @Test
    func `Refused subscriptions end setup with the redacted server error`() async {
        let socket = SocketFixture { data, ordinal in
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let id = try #require(body["id"] as? String)
            guard ordinal == 2 else { return [Data(#"{"jsonrpc":"2.0","id":"\#(id)","result":1}"#.utf8)] }
            return [Data(#"{"jsonrpc":"2.0","id":"\#(id)","error":{"code":-32601,"message":"fixture-key Method not found"}}"#.utf8)]
        }
        await #expect(throws: RPCError.server(code: -32601, message: "[redacted] Method not found")) {
            try await client(socket: socket).events(for: "fixture-signature")
        }
        #expect(socket.requests.count == 2)
        #expect(socket.isCancelled)
    }
}
