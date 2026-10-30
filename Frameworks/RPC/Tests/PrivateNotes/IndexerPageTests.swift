import Foundation
import Testing
@testable import RPC

struct IndexerPageTests {
    private typealias Fixture = IndexerFixtures

    @Test
    func `Transaction pages decode their rows cursors and output tree`() throws {
        let json = page(Fixture.page([Fixture.transaction(signature: 1, slot: 9_007_199_254_740_993, eventIndex: 3,
                                                          outputs: [Fixture.output(tag: 1, hash: 2, leafIndex: 7)],
                                                          nullifiers: [4, 5])],
                                     next: "AQ==", scanned: "Ag==", outputTreeID: 6))

        let decoded = try JSONDecoder().decode(ShieldedTransactionPage.self, from: json)

        #expect(decoded.items.map(\.isInRing) == [false])
        #expect(decoded.items.map(\.value) == [ShieldedTransaction(
            signature: Fixture.signature(1), slot: 9_007_199_254_740_993, eventIndex: 3,
            transactionViewingKey: Array(repeating: 2, count: 33), salt: Array(repeating: 5, count: 16),
            outputs: [ShieldedOutput(viewTag: Fixture.bytes(1), utxoHash: Fixture.bytes(2), treeID: 0, leafIndex: 7,
                                     payload: [1, 2, 3])],
            nullifiers: [Fixture.bytes(4), Fixture.bytes(5)], isProofless: false
        )])
        #expect(decoded.nextCursor == "AQ==")
        #expect(decoded.scannedThrough == "Ag==")
        #expect(decoded.outputTreeID == 6)
    }

    @Test
    func `Absent and null optional fields decode as absent`() throws {
        let transaction = #"{"slot":1,"txSignature":"\#(Fixture.signature(1))","outputSlots":[],"nullifiers":[],"proofless":true}"#
        let json = Data(#"{"transactions":[\#(transaction)],"nextCursor":null}"#.utf8)

        let decoded = try JSONDecoder().decode(ShieldedTransactionPage.self, from: json)

        let row = try #require(decoded.items.first?.value)
        #expect(row.eventIndex == nil)
        #expect(row.transactionViewingKey == nil)
        #expect(row.salt == nil)
        #expect(decoded.nextCursor == nil)
        #expect(decoded.scannedThrough == nil)
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
        (#""nextCursor":"AQ==""#, #""nextCursor":"AQ""#),
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
        let output = Fixture.output(tag: 1, hash: 2, leafIndex: 7)
        let json = page(Fixture.page([Fixture.match(signature: 1, slot: 10, output: output),
                                      Fixture.match(signature: 2, slot: 11, output: output, keyed: true)],
                                     in: "matches", outputTreeID: 3))

        let decoded = try JSONDecoder().decode(EncryptedOutputPage.self, from: json)

        let expected = ShieldedOutput(viewTag: Fixture.bytes(1), utxoHash: Fixture.bytes(2), treeID: 0, leafIndex: 7,
                                      payload: [1, 2, 3])
        #expect(decoded.items.map(\.output) == [expected, expected])
        #expect(decoded.items.map(\.deposit) == [
            ShieldedTransaction(signature: Fixture.signature(1), slot: 10, eventIndex: nil, transactionViewingKey: nil,
                                salt: nil, outputs: [expected], nullifiers: [], isProofless: true),
            nil,
        ])
        #expect(decoded.outputTreeID == 3)
    }

    @Test
    func `Reading pages collects rows until no cursor remains`() async throws {
        let pages = [
            nil: Fixture.page([Fixture.transaction(signature: 1, slot: 1)], next: "AQ==", outputTreeID: 1),
            "AQ==": Fixture.page(scanned: "Ag=="),
        ] as [String?: String]

        let read = try await ShieldedTransactionPage.readAll(from: nil) { cursor in
            try JSONDecoder().decode(ShieldedTransactionPage.self, from: page(try #require(pages[cursor])))
        }

        #expect(read.items.map(\.value.slot) == [1])
        #expect(read.outputTreeID == 1)
        #expect(read.resumeCursor == "Ag==")
    }

    @Test
    func `A cursor on a page without rows fails the read`() async {
        await #expect(throws: RPCError.invalidResponse(.invalidCursor)) {
            try await ShieldedTransactionPage.readAll(from: nil) { _ in
                try JSONDecoder().decode(ShieldedTransactionPage.self, from: page(IndexerFixtures.page(next: "AQ==")))
            }
        }
    }

    private func page(_ member: String) -> Data {
        Data(member.dropFirst(#""result":"#.count).utf8)
    }
}
