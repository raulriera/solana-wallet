import Encoding
import Foundation
import Testing
@testable import RPC

struct ZolanaPrivateNotesTests {
    private typealias Fixture = IndexerFixtures

    private static let unansweredProofs: [([String], [(leaf: UInt8, tree: UInt8)])] = [
        ([IndexerFixtures.merkleProof(leaf: 8), IndexerFixtures.merkleProof(leaf: 7)], [(8, 9), (7, 9)]),
        ([IndexerFixtures.merkleProof(leaf: 7)], [(7, 9)]),
        ([IndexerFixtures.merkleProof(leaf: 7), IndexerFixtures.merkleProof(leaf: 6), IndexerFixtures.merkleProof(leaf: 8)],
         [(7, 9), (6, 9), (8, 9)]),
        ([IndexerFixtures.merkleProof(leaf: 7), IndexerFixtures.merkleProof(leaf: 8, tree: IndexerFixtures.hash(4))],
         [(7, 9), (8, 4)]),
    ]

    @Test(arguments: IndexerFixtures.hosts)
    func `Tag reads post to each stream's route at the network's indexer`(network: Network, host: String) async throws {
        let transport = StubTransport { try reply(to: $0, payload: Fixture.page(in: rows(for: $0))) }
        let rpc = Zolana(network: network, transport: transport)

        _ = try await rpc.shieldedTransactions(taggedWith: [Fixture.bytes(1)], after: nil)

        let requests = await transport.requests.sorted { ($0.url?.path() ?? "") < ($1.url?.path() ?? "") }
        #expect(requests.map { $0.url?.absoluteString } == [
            "https://\(host)/getEncryptedUtxosByTags",
            "https://\(host)/getShieldedTransactionsByTags",
        ])
        let bodies = try requests.map(requestBody)
        #expect(bodies.map { $0["method"] as? String } == [GetEncryptedUtxosByTags.method, GetShieldedTransactionsByTags.method])
        #expect(bodies.map { $0["params"] as? [String: [String]] } == Array(repeating: ["tags": [Fixture.hash(1)]], count: 2))
        #expect(requests.map(\.httpMethod) == ["POST", "POST"])
    }

    @Test
    func `Tag reads follow cursors until a page has none`() async throws {
        let transport = StubTransport { request in
            let (route, params) = try Fixture.call(request)
            guard route == GetShieldedTransactionsByTags.method else { return try reply(to: request, payload: Fixture.page(in: "matches")) }
            return switch params["cursor"] as? String {
            case nil: try reply(to: request, payload: Fixture.page([Fixture.transaction(signature: 1, slot: 10)], next: "AQ=="))
            case "AQ==": try reply(to: request, payload: Fixture.page([Fixture.transaction(signature: 2, slot: 11)], next: "Ag=="))
            default: try reply(to: request, payload: Fixture.page(scannedThrough: "Aw=="))
            }
        }
        let rpc = Zolana(network: .devnet, transport: transport)

        let batch = try await rpc.shieldedTransactions(taggedWith: [Fixture.bytes(1)], after: nil)

        #expect(batch.transactions.map(\.signature) == [Fixture.signature(1), Fixture.signature(2)])
        #expect(!batch.moreComing)
        let cursors = try await transport.requests.map(Fixture.call)
            .filter { $0.route == GetShieldedTransactionsByTags.method }.map { $0.params["cursor"] as? String }
        #expect(cursors == [nil, "AQ==", "Ag=="])
    }

    @Test
    func `Tag reads stop at the page limit and say more is coming`() async throws {
        let transport = pagedTransactions(endingAt: nil)
        let rpc = Zolana(network: .devnet, transport: transport)
        let tags = [Fixture.bytes(1)]

        let batch = try await rpc.shieldedTransactions(taggedWith: tags, after: nil)

        #expect(batch.moreComing)
        #expect(batch.transactions.map(\.slot) == [1, 2, 3, 4, 5, 6, 7, 8])
        let resumed = PageCursor.cursor(forPage: 8)
        #expect(batch.position == NoteSyncPosition(tags: tags, transactionCursors: [resumed],
                                                   outputCursors: [IndexerReplies.scannedThrough]))
        let routes = await transport.requests.map { $0.url?.lastPathComponent }
        #expect(routes.filter { $0 == GetShieldedTransactionsByTags.method }.count == 8)
    }

    @Test
    func `A backlog longer than one read is read over several reads`() async throws {
        let rpc = Zolana(network: .devnet, transport: pagedTransactions(endingAt: 9))
        let tags = [Fixture.bytes(1)]

        let first = try await rpc.shieldedTransactions(taggedWith: tags, after: nil)
        let second = try await rpc.shieldedTransactions(taggedWith: tags, after: first.position)

        #expect(first.moreComing)
        #expect(!second.moreComing)
        #expect((first.transactions + second.transactions).map(\.slot) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        #expect(second.position == NoteSyncPosition(tags: tags, transactionCursors: [IndexerReplies.scannedThrough],
                                                    outputCursors: [IndexerReplies.scannedThrough]))
    }

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
            let row = isTransactions ? Fixture.transaction(signature: 1, slot: 1)
                : Fixture.match(signature: 1, slot: 1, output: Fixture.output(tag: 1, hash: 1, leafIndex: 1))
            return try reply(to: request, payload: Fixture.page(page.0 == nil ? [] : [row],
                                                                in: isTransactions ? "transactions" : "matches",
                                                                next: page.0, scannedThrough: page.1))
        }
        let rpc = Zolana(network: .devnet, transport: transport)
        let tags = [Fixture.bytes(1)]
        let start = NoteSyncPosition(tags: tags, transactionCursors: ["start"], outputCursors: ["start"])

        let batch = try await rpc.shieldedTransactions(taggedWith: tags, after: start)

        #expect(batch.position == NoteSyncPosition(tags: tags, transactionCursors: [expected], outputCursors: [expected]))
    }

    @Test
    func `Deposits come only from unkeyed outputs of the deposit stream`() async throws {
        let deposit = Fixture.output(tag: 1, hash: 7, leafIndex: 4, payload: "AAID")
        let transport = StubTransport { request in
            let (route, _) = try Fixture.call(request)
            return try reply(to: request, payload: route == GetShieldedTransactionsByTags.method
                ? Fixture.page([Fixture.transaction(signature: 1, slot: 10, proofless: true, outputs: [deposit]),
                                Fixture.transaction(signature: 2, slot: 12, outputs: [deposit], nullifiers: [8])])
                : Fixture.page([Fixture.match(signature: 1, slot: 10, output: deposit),
                                Fixture.match(signature: 2, slot: 12, output: deposit, keyed: true)], in: "matches"))
        }
        let rpc = Zolana(network: .devnet, transport: transport)

        let batch = try await rpc.shieldedTransactions(taggedWith: [Fixture.bytes(1)], after: nil)

        let output = ShieldedOutput(viewTag: Fixture.bytes(1), utxoHash: Fixture.bytes(7), treeID: 0, leafIndex: 4,
                                    payload: [0, 2, 3])
        #expect(batch.transactions == [
            ShieldedTransaction(signature: Fixture.signature(1), slot: 10, eventIndex: nil, transactionViewingKey: nil,
                                salt: nil, outputs: [output], nullifiers: [], isProofless: true),
            ShieldedTransaction(signature: Fixture.signature(2), slot: 12, eventIndex: 0,
                                transactionViewingKey: Array(repeating: 2, count: 33),
                                salt: Array(repeating: 5, count: 16), outputs: [output],
                                nullifiers: [Fixture.bytes(8)], isProofless: false),
        ])
    }

    @Test
    func `Tag groups of a thousand read separately and merge without repeats`() async throws {
        let transport = StubTransport { request in
            let (route, params) = try Fixture.call(request)
            let tags = try #require(params["tags"] as? [String])
            guard route == GetShieldedTransactionsByTags.method else {
                return try reply(to: request, payload: Fixture.page(in: "matches", scannedThrough: tags.count == 1 ? "Ag==" : "AQ=="))
            }
            let shared = Fixture.transaction(signature: 3, slot: 20)
            let own = tags.count == 1 ? Fixture.transaction(signature: 1, slot: 30) : Fixture.transaction(signature: 2, slot: 5)
            return try reply(to: request, payload: Fixture.page([shared, own], scannedThrough: tags.count == 1 ? "Ag==" : "AQ=="))
        }
        let rpc = Zolana(network: .devnet, transport: transport)
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

    @Test(arguments: [(UInt16?(2), UInt16?(3), UInt16?(2)), (nil, 3, 3), (nil, nil, nil)])
    func `The output tree prefers the transaction stream's report`(
        transactionTree: UInt16?, depositTree: UInt16?, expected: UInt16?
    ) async throws {
        let transport = StubTransport { request in
            let (route, _) = try Fixture.call(request)
            return try route == GetShieldedTransactionsByTags.method
                ? reply(to: request, payload: Fixture.page(outputTreeID: transactionTree))
                : reply(to: request, payload: Fixture.page(in: "matches", outputTreeID: depositTree))
        }
        let rpc = Zolana(network: .devnet, transport: transport)

        let batch = try await rpc.shieldedTransactions(taggedWith: [Fixture.bytes(1)], after: nil)

        #expect(batch.outputTreeID == expected)
    }

    @Test
    func `A read without tags sends no request`() async throws {
        let transport = StubTransport { try reply(to: $0, payload: Fixture.page()) }
        let rpc = Zolana(network: .devnet, transport: transport)

        let batch = try await rpc.shieldedTransactions(taggedWith: [], after: nil)

        #expect(batch.transactions.isEmpty)
        #expect(batch.outputTreeID == nil)
        #expect(batch.position == NoteSyncPosition(tags: [], groupCount: 0))
        #expect(await transport.requests.isEmpty)
    }

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
        let rpc = Zolana(network: .devnet, transport: transport)

        await #expect(throws: error) { try await rpc.shieldedTransactions(taggedWith: tags, after: position) }
        #expect(await transport.requests.isEmpty)
    }

    @Test(arguments: [[IndexerFixtures.transaction(signature: 1, slot: 1)], []])
    func `A cursor that can't advance fails the read`(rows: [String]) async {
        let transport = StubTransport { request in
            let (route, _) = try Fixture.call(request)
            return try route == GetShieldedTransactionsByTags.method
                ? reply(to: request, payload: Fixture.page(rows, next: "AQ=="))
                : reply(to: request, payload: Fixture.page(in: "matches"))
        }
        let rpc = Zolana(network: .devnet, transport: transport)

        await #expect(throws: RPCError.invalidResponse(.invalidCursor)) {
            try await rpc.shieldedTransactions(taggedWith: [Fixture.bytes(1)], after: nil)
        }
    }

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
        let rpc = Zolana(network: .devnet, transport: transport)

        let batch = try await rpc.shieldedTransactions(taggedWith: [Fixture.bytes(1)], after: nil)

        #expect(batch.transactions.map(\.signature) == [Fixture.signature(3)])
    }

    @Test
    func `Nullifier reads keep spends of other rings`() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: Fixture.page([Fixture.transaction(signature: 1, slot: 1, nullifiers: [1])
                .replacingOccurrences(of: #""proofless":false"#, with: #""proofless":false,"ringConfig":"\#(Fixture.hash(3))""#)]))
        }
        let rpc = Zolana(network: .devnet, transport: transport)

        #expect(try await rpc.shieldedTransactions(spending: [Fixture.bytes(1)]).map(\.signature) == [Fixture.signature(1)])
    }

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
        let rpc = Zolana(network: .devnet, transport: transport)

        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: nil)) {
            try await rpc.shieldedTransactions(taggedWith: [Fixture.bytes(1)], after: nil)
        }
        #expect(await transport.observedCancellation)
    }

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
        let rpc = Zolana(network: .devnet, transport: transport)
        let nullifiers = (0..<401).map { [UInt8](repeating: 0, count: 30) + [UInt8($0 >> 8), UInt8($0 & 0xff)] }

        let transactions = try await rpc.shieldedTransactions(spending: nullifiers)

        #expect(transactions.map(\.signature) == [Fixture.signature(5), Fixture.signature(4), Fixture.signature(9)])
        let requests = await transport.requests
        #expect(requests.count == 3)
        #expect(requests.allSatisfy {
            $0.url?.absoluteString == "https://d34xe1hqb2ibg2.cloudfront.net/getShieldedTransactionsByNullifiers"
        })
    }

    @Test
    func `Nullifier reads send groups of 400`() async throws {
        let transport = StubTransport { try reply(to: $0, payload: Fixture.page()) }
        let rpc = Zolana(network: .devnet, transport: transport)
        let nullifiers = (0..<401).map { [UInt8](repeating: 0, count: 30) + [UInt8($0 >> 8), UInt8($0 & 0xff)] }

        _ = try await rpc.shieldedTransactions(spending: nullifiers)

        let groups = try await transport.requests.map(Fixture.call).compactMap { $0.params["nullifiers"] as? [String] }
        #expect(groups.map(\.count).sorted() == [1, 400])
        #expect(Set(groups.flatMap(\.self)) == Set(nullifiers.map(Base58.encode)))
    }

    @Test
    func `Nullifier reads stop at the page limit`() async throws {
        let transport = StubTransport { request in
            let page = try PageCursor.page(of: request)
            let row = Fixture.transaction(signature: UInt8(page + 1), slot: page + 1, nullifiers: [1])
            return try reply(to: request, payload: Fixture.page([row], next: PageCursor.cursor(forPage: page + 1)))
        }
        let rpc = Zolana(network: .devnet, transport: transport)

        let transactions = try await rpc.shieldedTransactions(spending: [Fixture.bytes(1)])

        #expect(transactions.map(\.slot) == [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(await transport.requests.count == 8)
    }

    @Test
    func `Indexer responses of up to 1 MiB are read`() async throws {
        let rpc = Zolana(network: .devnet, transport: paddedReplies(length: 1_048_576))

        _ = try await rpc.shieldedTransactions(taggedWith: [Fixture.bytes(1)], after: nil)
        #expect(try await rpc.shieldedTransactions(spending: [Fixture.bytes(1)]).isEmpty)
    }

    @Test
    func `Indexer responses longer than 1 MiB are refused`() async {
        let rpc = Zolana(network: .devnet, transport: paddedReplies(length: 1_048_577))

        await #expect(throws: RPCError.invalidResponse(.oversized)) {
            try await rpc.shieldedTransactions(taggedWith: [Fixture.bytes(1)], after: nil)
        }
        await #expect(throws: RPCError.invalidResponse(.oversized)) {
            try await rpc.shieldedTransactions(spending: [Fixture.bytes(1)])
        }
    }

    @Test
    func `Nullifier reads refuse invalid nullifiers and skip empty ones`() async throws {
        let transport = StubTransport { try reply(to: $0, payload: Fixture.page()) }
        let rpc = Zolana(network: .devnet, transport: transport)

        await #expect(throws: PrivateNoteError.invalidNullifier) {
            try await rpc.shieldedTransactions(spending: [[UInt8](repeating: 1, count: 33)])
        }
        #expect(try await rpc.shieldedTransactions(spending: []).isEmpty)
        #expect(await transport.requests.isEmpty)
    }

    @Test(arguments: IndexerFixtures.hosts)
    func `Merkle proof reads post the tree and leaves to the network's indexer`(network: Network, host: String) async throws {
        let transport = StubTransport { request in
            let leaves = try #require(try Fixture.call(request).params["leaves"] as? [String])
            let bytes = try leaves.map { try #require(Base58.decode($0, byteCount: 32)?.first) }
            return try reply(to: request, payload: Fixture.proofs(bytes.map { Fixture.merkleProof(leaf: $0) }))
        }
        let rpc: any PrivateNoteProviding = Zolana(network: network, transport: transport)

        let proofs = try await rpc.merkleProofs(for: [Fixture.bytes(7), Fixture.bytes(8)], inTree: Fixture.hash(9))

        #expect(proofs.map(\.leaf) == [Fixture.bytes(7), Fixture.bytes(8)])
        let requests = await transport.requests
        #expect(requests.map { $0.url?.absoluteString } == ["https://\(host)/getMerkleProofs"])
        let bodies = try requests.map(requestBody)
        #expect(bodies.map { $0["method"] as? String } == [GetMerkleProofs.method])
        #expect(bodies.map { $0["params"] as? [String: AnyHashable] } == [
            ["treeAccount": Fixture.hash(9), "leaves": [Fixture.hash(7), Fixture.hash(8)]],
        ])
    }

    @Test(arguments: unansweredProofs)
    func `Merkle proofs that don't answer the request are returned as the indexer sent them`(
        proofs: [String],
        named: [(leaf: UInt8, tree: UInt8)]
    ) async throws {
        let transport = StubTransport { try reply(to: $0, payload: Fixture.proofs(proofs)) }
        let rpc = Zolana(network: .devnet, transport: transport)

        let returned = try await rpc.merkleProofs(for: [Fixture.bytes(7), Fixture.bytes(8)], inTree: Fixture.hash(9))

        #expect(returned.map(\.leaf) == named.map { Fixture.bytes($0.leaf) })
        #expect(returned.map(\.tree) == named.map { Fixture.bytes($0.tree) })
    }

    @Test
    func `Invalid or empty Merkle proof reads send nothing`() async throws {
        let transport = StubTransport { _ in throw CancellationError() }
        let rpc = Zolana(network: .devnet, transport: transport)
        let tree = Fixture.hash(9)

        #expect(try await rpc.merkleProofs(for: [], inTree: tree).isEmpty)
        await #expect(throws: PrivateNoteError.invalidLeaf) { try await rpc.merkleProofs(for: [[1]], inTree: tree) }
        await #expect(throws: PrivateNoteError.invalidTree) {
            try await rpc.merkleProofs(for: [Fixture.bytes(7)], inTree: "3QJmV3qfvL9SuYo34YihAf3sRCW3qSinyC")
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test
    func `Merkle proof reads send groups of 400 leaves and keep the leaves' order`() async throws {
        let leaves = (0..<1_001).map(Self.leaf)
        let encoded = leaves.map(Base58.encode)
        let transport = Self.answeringProofs { $0 }
        let rpc = Zolana(network: .devnet, transport: transport)

        let proofs = try await rpc.merkleProofs(for: leaves, inTree: Fixture.hash(9))

        #expect(proofs.map(\.leaf) == leaves)
        let groups = try await transport.requests.map { try #require(try Fixture.call($0).params["leaves"] as? [String]) }
        #expect(Set(groups) == [Array(encoded[0..<400]), Array(encoded[400..<800]), Array(encoded[800...])])
    }

    @Test
    func `A group of proofs that doesn't answer its leaves keeps its place in request order`() async throws {
        let transport = Self.answeringProofs { $0.count == 1 ? [Fixture.hash(0xee), Fixture.hash(0xef)] : $0 }
        let rpc = Zolana(network: .devnet, transport: transport)

        let proofs = try await rpc.merkleProofs(for: (0..<401).map(Self.leaf), inTree: Fixture.hash(9))

        #expect(proofs.map(\.leaf) == (0..<400).map(Self.leaf) + [Fixture.bytes(0xee), Fixture.bytes(0xef)])
    }

    @Test
    func `Merkle proof responses longer than 1 MiB are refused`() async {
        let payload = Fixture.proofs([Fixture.merkleProof(leaf: 7)])
        let rpc = Zolana(network: .devnet, transport: paddedReplies(length: 1_048_577, payload: payload))

        await #expect(throws: RPCError.invalidResponse(.oversized)) {
            try await rpc.merkleProofs(for: [Fixture.bytes(7)], inTree: Fixture.hash(9))
        }
    }

    private static func leaf(_ number: Int) -> [UInt8] {
        [UInt8](repeating: 0, count: 30) + [UInt8(number >> 8), UInt8(number & 0xff)]
    }

    private static func answeringProofs(_ answer: @escaping @Sendable ([String]) -> [String]) -> StubTransport {
        StubTransport { request in
            let leaves = try #require(try Fixture.call(request).params["leaves"] as? [String])
            return try reply(to: request, payload: Fixture.proofs(answer(leaves).map { Fixture.merkleProof(leafHash: $0) }))
        }
    }
}

private func rows(for request: URLRequest) -> String {
    request.url?.lastPathComponent == GetEncryptedUtxosByTags.method ? "matches" : "transactions"
}

private func pagedTransactions(endingAt lastPage: Int?) -> StubTransport {
    StubTransport { request in
        guard try IndexerFixtures.call(request).route == GetShieldedTransactionsByTags.method else {
            return try reply(to: request, payload: IndexerFixtures.page(in: "matches"))
        }
        let page = try PageCursor.page(of: request)
        let row = IndexerFixtures.transaction(signature: UInt8(page + 1), slot: page + 1)
        let next = page == lastPage ? nil : PageCursor.cursor(forPage: page + 1)
        return try reply(to: request, payload: IndexerFixtures.page([row], next: next))
    }
}

private func paddedReplies(length: Int, payload: String? = nil) -> StubTransport {
    StubTransport { request in
        let (data, response) = try reply(to: request, payload: payload ?? IndexerFixtures.page(in: rows(for: request)))
        return (data + Data(repeating: 0x20, count: length - data.count), response)
    }
}
