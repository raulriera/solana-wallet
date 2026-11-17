import Foundation
import Testing
@testable import RPC

struct IndexerPageTests {
    private typealias Fixture = IndexerFixtures

    @Test
    func `Transaction pages decode their rows, token, context slot, and output tree`() throws {
        let json = page(Fixture.page([Fixture.transaction(signature: 1, slot: 9_007_199_254_740_993, eventIndex: 3,
                                                          outputs: [Fixture.output(tag: 1, hash: 2, leafIndex: 7)],
                                                          nullifiers: [4, 5])],
                                     next: "AQ==", outputTreeID: 6))

        let decoded = try JSONDecoder().decode(ShieldedTransactionPage.self, from: json)
        let last = try JSONDecoder().decode(ShieldedTransactionPage.self, from: page(Fixture.page(contextSlot: 7)))

        #expect(decoded.items.map(\.isInRing) == [false])
        #expect(decoded.items.map(\.value) == [ShieldedTransaction(
            signature: Fixture.signature(1), slot: 9_007_199_254_740_993, eventIndex: 3,
            transactionViewingKey: Array(repeating: 2, count: 33), salt: Array(repeating: 5, count: 16),
            outputs: [ShieldedOutput(viewTag: Fixture.bytes(1), utxoHash: Fixture.bytes(2), treeID: 0, leafIndex: 7,
                                     payload: [1, 2, 3])],
            nullifiers: [Fixture.bytes(4), Fixture.bytes(5)], isProofless: false
        )])
        #expect(decoded.paginationToken == "AQ==")
        #expect(decoded.contextSlot == IndexerReplies.contextSlot)
        #expect(decoded.outputTreeID == 6)
        #expect(last.paginationToken == nil)
        #expect(last.contextSlot == 7)
    }

    @Test
    func `A transaction's events decode in order before the next transaction's`() throws {
        let json = page(Fixture.page([Fixture.transaction(signature: 1, slot: 4, eventIndex: 0),
                                      Fixture.transaction(signature: 1, slot: 4, eventIndex: 1),
                                      Fixture.transaction(signature: 2, slot: 5)]))

        let decoded = try JSONDecoder().decode(ShieldedTransactionPage.self, from: json)

        #expect(decoded.items.map(\.value.signature) == [Fixture.signature(1), Fixture.signature(1), Fixture.signature(2)])
        #expect(decoded.items.map(\.value.eventIndex) == [0, 1, 0])
    }

    @Test
    func `Absent and null optional fields decode as absent`() throws {
        let transaction = #"{"slot":1,"txSignature":"\#(Fixture.signature(1))","outputSlots":[],"nullifiers":[],"proofless":true}"#
        let entry = #"{"slot":1,"signature":"\#(Fixture.signature(1))","events":[\#(transaction)]}"#
        let json = Data(#"{"context":{"blockTime":1,"slot":3},"data":[\#(entry)],"paginationToken":null}"#.utf8)

        let decoded = try JSONDecoder().decode(ShieldedTransactionPage.self, from: json)

        let row = try #require(decoded.items.first?.value)
        #expect(row.eventIndex == nil)
        #expect(row.transactionViewingKey == nil)
        #expect(row.salt == nil)
        #expect(decoded.paginationToken == nil)
        #expect(decoded.outputTreeID == nil)
    }

    @Test(arguments: [
        (IndexerFixtures.hash(4), "11111111111111111111111111111111111"),
        (IndexerFixtures.viewingKey, Data(repeating: 2, count: 32).base64EncodedString()),
        (IndexerFixtures.salt, "BQUFBQUFBQUFBQUFBQUFBQ"),
        (IndexerFixtures.signature(1), IndexerFixtures.hash(1)),
        (#""slot":10"#, #""slot":"10""#),
        (#""leafIndex":7"#, #""leafIndex":-7"#),
        (#""treeId":0"#, #""treeId":65536"#),
        (#","proofless":false"#, ""),
        (#""payload":"AQID""#, #""payload":"AQID=""#),
        (#""paginationToken":"AQ==""#, #""paginationToken":"""#),
        (#""paginationToken":"AQ==""#, ""),
        (#""context":{"blockTime":1,"slot":2}"#, #""context":{"blockTime":1}"#),
        (#""events":["#, #""transactions":["#),
    ] as [(String, String)])
    func `Malformed transaction pages fail to decode`(field: String, replacement: String) throws {
        let valid = String(decoding: page(Fixture.page([Fixture.transaction(
            signature: 1, slot: 10, outputs: [Fixture.output(tag: 1, hash: 2, leafIndex: 7)], nullifiers: [4]
        )], next: "AQ==")), as: UTF8.self)
        try #require(valid.contains(field))

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ShieldedTransactionPage.self, from: Data(valid.replacingOccurrences(of: field, with: replacement).utf8))
        }
    }

    @Test(arguments: [
        ("ringConfig", "\"" + IndexerFixtures.hash(3) + "\"", true),
        ("ringProgramId", "\"" + IndexerFixtures.hash(3) + "\"", true),
        ("ringConfig", "null", false),
    ] as [(String, String, Bool)])
    func `Rows that name a ring are marked`(field: String, value: String, isInRing: Bool) throws {
        let row = Fixture.transaction(signature: 1, slot: 1)
            .replacingOccurrences(of: #""proofless":false"#, with: #""proofless":false,"\#(field)":\#(value)"#)

        let decoded = try JSONDecoder().decode(ShieldedTransactionPage.self, from: page(Fixture.page([row])))

        #expect(decoded.items.map(\.isInRing) == [isInRing])
    }

    @Test(arguments: ["ringConfig", "ringProgramId"])
    func `Malformed ring fields fail to decode`(field: String) {
        let row = Fixture.transaction(signature: 1, slot: 1)
            .replacingOccurrences(of: #""proofless":false"#, with: #""proofless":false,"\#(field)":"1""#)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ShieldedTransactionPage.self, from: page(Fixture.page([row])))
        }
    }

    @Test
    func `Encrypted outputs are deposits only without a viewing key and salt`() throws {
        let output = Fixture.output(tag: 1, hash: 2, leafIndex: 7, payload: "AAID")
        let json = page(Fixture.page([Fixture.match(signature: 1, slot: 10, output: output),
                                      Fixture.match(signature: 2, slot: 11, output: output, keyed: true)],
                                     in: "outputs", outputTreeID: 3))

        let decoded = try JSONDecoder().decode(EncryptedOutputPage.self, from: json)

        let expected = ShieldedOutput(viewTag: Fixture.bytes(1), utxoHash: Fixture.bytes(2), treeID: 0, leafIndex: 7,
                                      payload: [0, 2, 3])
        #expect(decoded.items.map(\.output) == [expected, expected])
        #expect(decoded.items.map(\.deposit) == [
            ShieldedTransaction(signature: Fixture.signature(1), slot: 10, eventIndex: nil, transactionViewingKey: nil,
                                salt: nil, outputs: [expected], nullifiers: [], isProofless: true),
            nil,
        ])
        #expect(decoded.outputTreeID == 3)
    }

    @Test(arguments: ["AQID", "AgID", ""])
    func `Unkeyed outputs without a plaintext payload aren't deposits`(payload: String) throws {
        let output = Fixture.output(tag: 1, hash: 2, leafIndex: 7, payload: payload)
        let json = page(Fixture.page([Fixture.match(signature: 1, slot: 10, output: output)], in: "outputs"))

        let decoded = try JSONDecoder().decode(EncryptedOutputPage.self, from: json)

        #expect(decoded.items.map(\.deposit) == [nil])
    }

    @Test
    func `Reading pages collects rows until no token remains`() async throws {
        let pages = [
            nil: Fixture.page([Fixture.transaction(signature: 1, slot: 1)], next: "AQ==", outputTreeID: 1),
            "AQ==": Fixture.page(contextSlot: 7),
        ] as [String?: String]

        let read = try await ShieldedTransactionPage.read(from: .start, pageLimit: 8, pageSize: 250) { checkpoint, _ in
            try JSONDecoder().decode(ShieldedTransactionPage.self,
                                     from: page(try #require(pages[checkpoint.paginationToken])))
        }

        #expect(read.items.map(\.value.slot) == [1])
        #expect(read.outputTreeID == 1)
        #expect(read.resume == IndexerCheckpoint(afterSlot: 7, paginationToken: nil))
        #expect(read.isComplete)
    }

    @Test
    func `A read keeps its start slot while it follows tokens and resumes at its next page`() async throws {
        var checkpoints: [IndexerCheckpoint] = []
        let endless = { (checkpoint: IndexerCheckpoint, _: Int) in
            checkpoints.append(checkpoint)
            return EndlessPage(items: [checkpoints.count], paginationToken: "\(checkpoints.count)")
        }
        let start = IndexerCheckpoint(afterSlot: 5, paginationToken: nil)

        let first = try await EndlessPage.read(from: start, pageLimit: 2, pageSize: 250, fetching: endless)
        let second = try await EndlessPage.read(from: first.resume, pageLimit: 2, pageSize: 250, fetching: endless)

        #expect(first.items == [1, 2])
        #expect(!first.isComplete)
        #expect(first.resume == IndexerCheckpoint(afterSlot: 5, paginationToken: "2"))
        #expect(second.items == [3, 4])
        let tokens: [String?] = [nil, "1", "2", "3"]
        #expect(checkpoints == tokens.map { IndexerCheckpoint(afterSlot: 5, paginationToken: $0) })
    }

    @Test
    func `A read that reaches the end of its stream resumes after its last page's slot`() async throws {
        var fetched = 0

        let read = try await EndlessPage.read(from: .start, pageLimit: 2, pageSize: 250) { _, _ in
            fetched += 1
            return EndlessPage(items: [fetched], paginationToken: fetched == 2 ? nil : "\(fetched)")
        }

        #expect(read.items == [1, 2])
        #expect(read.isComplete)
        #expect(read.resume == IndexerCheckpoint(afterSlot: EndlessPage.contextSlot, paginationToken: nil))
    }

    @Test
    func `A token on a page without rows fails the read`() async {
        await #expect(throws: RPCError.invalidResponse(.invalidCursor)) {
            try await ShieldedTransactionPage.read(from: .start, pageLimit: 8, pageSize: 250) { _, _ in
                try JSONDecoder().decode(ShieldedTransactionPage.self, from: page(IndexerFixtures.page(next: "AQ==")))
            }
        }
    }

    @Test
    func `A page that is too long halves the page size for the rest of the read`() async throws {
        var sizes: [Int] = []

        let read = try await EndlessPage.read(from: .start, pageLimit: 2, pageSize: 250) { _, size in
            sizes.append(size)
            guard size < 40 else { throw RPCError.invalidResponse(.oversized) }
            return EndlessPage(items: [size], paginationToken: "\(sizes.count)")
        }

        #expect(sizes == [250, 125, 62, 31, 31])
        #expect(read.items == [31, 31])
    }

    @Test
    func `A one-transaction page that is too long fails the read`() async {
        var sizes: [Int] = []

        await #expect(throws: RPCError.invalidResponse(.oversized)) {
            try await EndlessPage.read(from: .start, pageLimit: 2, pageSize: 4) { _, size in
                sizes.append(size)
                throw RPCError.invalidResponse(.oversized)
            }
        }
        #expect(sizes == [4, 2, 1])
    }

    private func page(_ member: String) -> Data {
        Data(member.dropFirst(#""result":"#.count).utf8)
    }
}

private nonisolated struct EndlessPage: IndexerPage {
    static let contextSlot: UInt64 = 40

    let items: [Int]
    let paginationToken: String?
    var outputTreeID: UInt16? { nil }
    var contextSlot: UInt64 { Self.contextSlot }
}
