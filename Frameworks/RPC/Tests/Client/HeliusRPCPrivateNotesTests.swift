import Encoding
import Foundation
import Testing
@testable import RPC

/// Exercises private-note reads through the real Helius client and recorded indexer responses.
struct HeliusRPCPrivateNotesTests {
    private typealias Fixture = IndexerFixtures

    /// Verifies both streams post JSON-RPC to their method routes below the gateway, with the key in the query.
    ///
    /// - Parameters:
    ///   - network: The selected network.
    ///   - host: The Helius host that serves it.
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test(arguments: [(Network.mainnet, "mainnet.helius-rpc.com"), (.devnet, "devnet.helius-rpc.com")])
    func `Tag reads post to each stream's route below the gateway`(network: Network, host: String) async throws {
        let transport = StubTransport { try reply(to: $0, payload: Fixture.page(in: rows(for: $0))) }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: network, transport: transport)

        _ = try await rpc.shieldedTransactions(taggedWith: [Fixture.bytes(1)], after: nil)

        let requests = await transport.requests.sorted { ($0.url?.path() ?? "") < ($1.url?.path() ?? "") }
        #expect(requests.map { $0.url?.absoluteString } == [
            "https://\(host)/v1/zolana/getEncryptedUtxosByTags?api-key=fixture-key",
            "https://\(host)/v1/zolana/getShieldedTransactionsByTags?api-key=fixture-key",
        ])
        let bodies = try requests.map(requestBody)
        #expect(bodies.map { $0["method"] as? String } == [GetEncryptedUtxosByTags.method, GetShieldedTransactionsByTags.method])
        #expect(bodies.map { $0["params"] as? [String: [String]] } == Array(repeating: ["tags": [Fixture.hash(1)]], count: 2))
        #expect(requests.map(\.httpMethod) == ["POST", "POST"])
    }

    /// Verifies a stream reads on after a short page and stops only at a page without a cursor.
    ///
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test
    func `Tag reads follow cursors until a page has none`() async throws {
        let transport = StubTransport { request in
            let (route, params) = try Fixture.call(request)
            guard route == GetShieldedTransactionsByTags.method else { return try reply(to: request, payload: Fixture.page(in: "matches")) }
            return switch params["cursor"] as? String {
            case nil: try reply(to: request, payload: Fixture.page([Fixture.transaction(signature: 1, slot: 10)], next: "AQ=="))
            case "AQ==": try reply(to: request, payload: Fixture.page([Fixture.transaction(signature: 2, slot: 11)], next: "Ag=="))
            default: try reply(to: request, payload: Fixture.page(next: nil, scanned: "Aw=="))
            }
        }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)

        let batch = try await rpc.shieldedTransactions(taggedWith: [Fixture.bytes(1)], after: nil)

        #expect(batch.transactions.map(\.signature) == [Fixture.signature(1), Fixture.signature(2)])
        let cursors = try await transport.requests.map(Fixture.call)
            .filter { $0.route == GetShieldedTransactionsByTags.method }.map { $0.params["cursor"] as? String }
        #expect(cursors == [nil, "AQ==", "Ag=="])
    }

    /// Verifies where a stream resumes: its terminal page's scanned position, else the last cursor it used,
    /// else the position it started from.
    ///
    /// - Parameters:
    ///   - pages: Each page's next cursor and scanned position, by the cursor that requests it.
    ///   - expected: The stream's resume cursor.
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test(arguments: [
        (["start": ("AQ==", nil), "AQ==": (nil, "Aw==")], "Aw=="),
        (["start": ("AQ==", nil), "AQ==": (nil, nil)], "AQ=="),
        (["start": (nil, nil)], "start"),
    ] as [([String: (String?, String?)], String)])
    func `Positions resume after the furthest point each stream reached`(
        pages: [String: (String?, String?)], expected: String
    ) async throws {
        let transport = StubTransport { request in
            let (route, params) = try Fixture.call(request)
            let cursor = try #require(params["cursor"] as? String)
            let page = try #require(pages[cursor])
            let isTransactions = route == GetShieldedTransactionsByTags.method
            // A page with a cursor has a row; the indexer sets one only on a page with rows.
            let row = isTransactions ? Fixture.transaction(signature: 1, slot: 1)
                : Fixture.match(signature: 1, slot: 1, output: Fixture.output(tag: 1, hash: 1, leafIndex: 1))
            return try reply(to: request, payload: Fixture.page(page.0 == nil ? [] : [row],
                                                                in: isTransactions ? "transactions" : "matches",
                                                                next: page.0, scanned: page.1))
        }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)
        let tags = [Fixture.bytes(1)]
        let start = NoteSyncPosition(tags: tags, transactionCursors: ["start"], outputCursors: ["start"])

        let batch = try await rpc.shieldedTransactions(taggedWith: tags, after: start)

        #expect(batch.position == NoteSyncPosition(tags: tags, transactionCursors: [expected], outputCursors: [expected]))
    }

    /// Verifies only outputs without a viewing key and salt become deposits, and that proofless rows of the
    /// transaction stream are dropped, since the deposit stream supplies them.
    ///
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test
    func `Deposits come only from unkeyed outputs of the deposit stream`() async throws {
        let deposit = Fixture.output(tag: 1, hash: 7, leafIndex: 4)
        let transport = StubTransport { request in
            let (route, _) = try Fixture.call(request)
            return try reply(to: request, payload: route == GetShieldedTransactionsByTags.method
                ? Fixture.page([Fixture.transaction(signature: 1, slot: 10, proofless: true, outputs: [deposit]),
                                Fixture.transaction(signature: 2, slot: 12, outputs: [deposit], nullifiers: [8])])
                : Fixture.page([Fixture.match(signature: 1, slot: 10, output: deposit),
                                Fixture.match(signature: 2, slot: 12, output: deposit, keyed: true)], in: "matches"))
        }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)

        let batch = try await rpc.shieldedTransactions(taggedWith: [Fixture.bytes(1)], after: nil)

        let output = ShieldedOutput(viewTag: Fixture.bytes(1), utxoHash: Fixture.bytes(7), treeID: 0, leafIndex: 4,
                                    payload: [1, 2, 3])
        #expect(batch.transactions == [
            ShieldedTransaction(signature: Fixture.signature(1), slot: 10, eventIndex: nil, transactionViewingKey: nil,
                                salt: nil, outputs: [output], nullifiers: [], isProofless: true),
            ShieldedTransaction(signature: Fixture.signature(2), slot: 12, eventIndex: 0,
                                transactionViewingKey: Array(repeating: 2, count: 33),
                                salt: Array(repeating: 5, count: 16), outputs: [output],
                                nullifiers: [Fixture.bytes(8)], isProofless: false),
        ])
    }

    /// Verifies more than 1,000 tags split into requests that each read their own cursor, and that a
    /// transaction that several requests return appears once, in slot and signature order.
    ///
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test
    func `Tag groups of a thousand read separately and merge without repeats`() async throws {
        let transport = StubTransport { request in
            let (route, params) = try Fixture.call(request)
            let tags = try #require(params["tags"] as? [String])
            guard route == GetShieldedTransactionsByTags.method else {
                return try reply(to: request, payload: Fixture.page(in: "matches", scanned: tags.count == 1 ? "Ag==" : "AQ=="))
            }
            let shared = Fixture.transaction(signature: 3, slot: 20)
            let own = tags.count == 1 ? Fixture.transaction(signature: 1, slot: 30) : Fixture.transaction(signature: 2, slot: 5)
            return try reply(to: request, payload: Fixture.page([shared, own], scanned: tags.count == 1 ? "Ag==" : "AQ=="))
        }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)
        let tags = (0..<1_001).map { [UInt8](repeating: 0, count: 30) + [UInt8($0 >> 8), UInt8($0 & 0xff)] }

        let batch = try await rpc.shieldedTransactions(taggedWith: tags, after: nil)

        #expect(batch.transactions.map(\.slot) == [5, 20, 30])
        #expect(batch.position == NoteSyncPosition(tags: tags, transactionCursors: ["AQ==", "Ag=="],
                                                   outputCursors: ["AQ==", "Ag=="]))
        let groups = try await transport.requests.map(Fixture.call)
            .filter { $0.route == GetShieldedTransactionsByTags.method }.compactMap { $0.params["tags"] as? [String] }
        #expect(groups.map(\.count).sorted() == [1, 1_000])
        #expect(Set(groups.flatMap(\.self)) == Set(tags.map(Base58.encode)))
    }

    /// Verifies the output tree comes from the transaction stream when it reports one, else the deposit stream.
    ///
    /// - Parameters:
    ///   - transactionTree: The transaction stream's output tree, or `nil` to omit it.
    ///   - depositTree: The deposit stream's output tree, or `nil` to omit it.
    ///   - expected: The batch's output tree.
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test(arguments: [(Int?(2), Int?(3), UInt16?(2)), (nil, 3, 3), (nil, nil, nil)])
    func `The output tree prefers the transaction stream's report`(
        transactionTree: Int?, depositTree: Int?, expected: UInt16?
    ) async throws {
        let transport = StubTransport { request in
            let (route, _) = try Fixture.call(request)
            return try route == GetShieldedTransactionsByTags.method
                ? reply(to: request, payload: Fixture.page(outputTreeID: transactionTree))
                : reply(to: request, payload: Fixture.page(in: "matches", outputTreeID: depositTree))
        }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)

        let batch = try await rpc.shieldedTransactions(taggedWith: [Fixture.bytes(1)], after: nil)

        #expect(batch.outputTreeID == expected)
    }

    /// Verifies a read without tags keeps its position and sends no request.
    ///
    /// - Throws: An RPC error, or a failed test prerequisite.
    @Test
    func `A read without tags sends no request`() async throws {
        let transport = StubTransport { try reply(to: $0, payload: Fixture.page()) }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)

        let batch = try await rpc.shieldedTransactions(taggedWith: [], after: nil)

        #expect(batch.transactions.isEmpty)
        #expect(batch.outputTreeID == nil)
        #expect(batch.position == NoteSyncPosition(tags: [], groupCount: 0))
        #expect(await transport.requests.isEmpty)
    }

    /// Verifies invalid tags and positions are refused before networking.
    ///
    /// - Parameters:
    ///   - tags: The requested tags.
    ///   - position: The starting position.
    ///   - error: The expected refusal.
    /// - Throws: A failed test prerequisite.
    @Test(arguments: [
        ([[UInt8](repeating: 1, count: 31)], NoteSyncPosition?.none, PrivateNoteError.invalidTag),
        ([IndexerFixtures.bytes(1)], NoteSyncPosition(tags: [IndexerFixtures.bytes(1)], groupCount: 2), .mismatchedPosition),
        ([IndexerFixtures.bytes(1)], NoteSyncPosition(tags: [IndexerFixtures.bytes(2)], groupCount: 1), .mismatchedPosition),
        ([IndexerFixtures.bytes(1), IndexerFixtures.bytes(2)],
         NoteSyncPosition(tags: [IndexerFixtures.bytes(2), IndexerFixtures.bytes(1)], groupCount: 1), .mismatchedPosition),
    ])
    func `Invalid tags and positions are refused before networking`(
        tags: [[UInt8]], position: NoteSyncPosition?, error: PrivateNoteError
    ) async {
        let transport = StubTransport { try reply(to: $0, payload: Fixture.page()) }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)

        await #expect(throws: error) { try await rpc.shieldedTransactions(taggedWith: tags, after: position) }
        #expect(await transport.requests.isEmpty)
    }

    /// Verifies a stream whose cursor can't advance fails instead of reading forever: a repeated cursor, or a
    /// cursor on a page without rows.
    ///
    /// - Parameter rows: The page's transactions.
    @Test(arguments: [[IndexerFixtures.transaction(signature: 1, slot: 1)], []])
    func `A cursor that can't advance fails the read`(rows: [String]) async {
        let transport = StubTransport { request in
            let (route, _) = try Fixture.call(request)
            return try route == GetShieldedTransactionsByTags.method
                ? reply(to: request, payload: Fixture.page(rows, next: "AQ=="))
                : reply(to: request, payload: Fixture.page(in: "matches"))
        }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.invalidResponse(.invalidCursor)) {
            try await rpc.shieldedTransactions(taggedWith: [Fixture.bytes(1)], after: nil)
        }
    }

    /// Verifies tag reads keep only the default ring: rows that name a ring's config account or program are dropped.
    ///
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test
    func `Tag reads drop transactions of other rings`() async throws {
        let transport = StubTransport { request in
            let (route, _) = try Fixture.call(request)
            guard route == GetShieldedTransactionsByTags.method else { return try reply(to: request, payload: Fixture.page(in: "matches")) }
            let withConfig = Fixture.transaction(signature: 1, slot: 1)
                .replacingOccurrences(of: #""proofless":false"#, with: #""proofless":false,"ringConfig":"\#(Fixture.hash(3))""#)
            let withProgram = Fixture.transaction(signature: 2, slot: 2)
                .replacingOccurrences(of: #""proofless":false"#, with: #""proofless":false,"ringProgramId":"\#(Fixture.hash(4))""#)
            let unnamed = Fixture.transaction(signature: 3, slot: 3)
                .replacingOccurrences(of: #""proofless":false"#, with: #""proofless":false,"ringConfig":null"#)
            return try reply(to: request, payload: Fixture.page([withConfig, withProgram, unnamed]))
        }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)

        let batch = try await rpc.shieldedTransactions(taggedWith: [Fixture.bytes(1)], after: nil)

        #expect(batch.transactions.map(\.signature) == [Fixture.signature(3)])
    }

    /// Verifies nullifier reads keep spends in any ring, since each consumes its nullifier.
    ///
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test
    func `Nullifier reads keep spends of other rings`() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: Fixture.page([Fixture.transaction(signature: 1, slot: 1, nullifiers: [1])
                .replacingOccurrences(of: #""proofless":false"#, with: #""proofless":false,"ringConfig":"\#(Fixture.hash(3))""#)]))
        }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)

        #expect(try await rpc.shieldedTransactions(spending: [Fixture.bytes(1)]).map(\.signature) == [Fixture.signature(1)])
    }

    /// Verifies a failing stream fails the read without waiting for the other stream to finish.
    ///
    /// The failing stream answers only after the other stream's request reaches the transport, so the
    /// cancellation always interrupts a request in flight.
    @Test(.timeLimit(.minutes(1)))
    func `A failing stream cancels the other`() async {
        let (inFlight, continuation) = AsyncStream.makeStream(of: Void.self)
        let transport = StubTransport { request in
            let (route, _) = try Fixture.call(request)
            guard route == GetShieldedTransactionsByTags.method else {
                continuation.yield()
                try await Task.sleep(for: .seconds(3_600))
                return try reply(to: request, payload: Fixture.page(in: "matches"))
            }
            var signals = inFlight.makeAsyncIterator()
            await signals.next()
            return try reply(to: request, payload: Fixture.page(), status: 429)
        }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: nil)) {
            try await rpc.shieldedTransactions(taggedWith: [Fixture.bytes(1)], after: nil)
        }
        #expect(await transport.observedCancellation)
    }

    /// Verifies nullifier reads post each group of at most 1,000 to the method's route, read every page, and
    /// return each spending transaction once in slot and signature order.
    ///
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test
    func `Nullifier reads merge every group's pages without repeats`() async throws {
        let transport = StubTransport { request in
            let (_, params) = try Fixture.call(request)
            let nullifiers = try #require(params["nullifiers"] as? [String])
            let shared = Fixture.transaction(signature: 4, slot: 40, nullifiers: [1])
            return switch (nullifiers.count, params["cursor"] as? String) {
            case (1, _): try reply(to: request, payload: Fixture.page([shared]))
            case (_, nil): try reply(to: request, payload: Fixture.page([Fixture.transaction(signature: 9, slot: 40)], next: "AQ=="))
            default: try reply(to: request, payload: Fixture.page([shared, Fixture.transaction(signature: 5, slot: 2)]))
            }
        }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)
        let nullifiers = (0..<1_001).map { [UInt8](repeating: 0, count: 30) + [UInt8($0 >> 8), UInt8($0 & 0xff)] }

        let transactions = try await rpc.shieldedTransactions(spending: nullifiers)

        #expect(transactions.map(\.signature) == [Fixture.signature(5), Fixture.signature(4), Fixture.signature(9)])
        let requests = await transport.requests
        #expect(requests.count == 3)
        #expect(requests.allSatisfy {
            $0.url?.absoluteString == "https://devnet.helius-rpc.com/v1/zolana/getShieldedTransactionsByNullifiers?api-key=fixture-key"
        })
    }

    /// Verifies a nullifier of another length is refused before networking, and no nullifiers send nothing.
    ///
    /// - Throws: An RPC error, or a failed test prerequisite.
    @Test
    func `Nullifier reads refuse invalid nullifiers and skip empty ones`() async throws {
        let transport = StubTransport { try reply(to: $0, payload: Fixture.page()) }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)

        await #expect(throws: PrivateNoteError.invalidNullifier) {
            try await rpc.shieldedTransactions(spending: [[UInt8](repeating: 1, count: 33)])
        }
        #expect(try await rpc.shieldedTransactions(spending: []).isEmpty)
        #expect(await transport.requests.isEmpty)
    }

    /// Verifies unsuccessful statuses surface as HTTP errors with a redacted retry delay.
    ///
    /// - Parameter status: A refusal, such as a rate limit, a missing key, or a timeout.
    @Test(arguments: [401, 408, 429])
    func `Indexer refusals surface as HTTP errors without the key`(status: Int) async {
        let transport = StubTransport { request in
            try reply(to: request, payload: Fixture.page(), status: status,
                      headers: ["Retry-After": "\(try #require(request.url?.absoluteString))"])
        }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.http(statusCode: status, retryAfter: "https://devnet.helius-rpc.com/v1/zolana/getShieldedTransactionsByNullifiers?api-key=[redacted]")) {
            try await rpc.shieldedTransactions(spending: [Fixture.bytes(1)])
        }
    }

    /// Verifies a server error that quotes the authenticated gateway URL loses the key.
    @Test
    func `Indexer errors omit the key`() async {
        let transport = StubTransport { request in
            let url = try #require(request.url?.absoluteString)
            return try reply(to: request, payload: #""error":{"code":-32600,"message":"Validation Error: \#(url)"}"#)
        }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.server(code: -32600, message: "Validation Error: https://devnet.helius-rpc.com/v1/zolana/getShieldedTransactionsByNullifiers?api-key=[redacted]")) {
            try await rpc.shieldedTransactions(spending: [Fixture.bytes(1)])
        }
    }
}

/// The row field of a stream's pages.
/// - Parameter request: An indexer request.
/// - Returns: `transactions` for the transaction stream, or `matches` for the deposit stream.
private func rows(for request: URLRequest) -> String {
    request.url?.lastPathComponent == GetEncryptedUtxosByTags.method ? "matches" : "transactions"
}
