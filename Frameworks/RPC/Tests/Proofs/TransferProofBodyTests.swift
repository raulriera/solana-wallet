import Foundation
import Testing
@testable import RPC

struct TransferProofBodyTests {
    private typealias Fixture = ProofFixtures

    @Test
    func `The body matches zolana's flat fields`() throws {
        let body = try json(Fixture.request())

        let utxo = ["domain": "0x3", "owner": "0x11", "asset": "0x0", "amount": "0xa1", "blinding": "0xb1",
                    "dataHash": "0x0", "ringDataHash": "0x0", "ringProgramId": "0x0"]
        let padding = utxo.merging(["domain": "0x1"]) { $1 }
        let unused = ["id": "0x0", "utxoRoot": "0x0", "nullifierRoot": "0x0"]
        let input: [String: AnyHashable] = [
            "utxo": utxo, "isDummy": "0x0", "treeSlot": "0x0", "nullifier": "0x21", "ownerPkHash": "0x31",
            "nullifierSecret": "0xc1", "statePathElements": (1...32).map { "0x" + String($0, radix: 16) }, "statePathIndex": "0x5",
            "nullifierLowValue": "0x20", "nullifierNextValue": "0x22",
            "nullifierLowPathElements": (0x81...0xa8).map { "0x" + String($0, radix: 16) }, "nullifierLowPathIndex": "0x9",
        ]
        #expect(body == [
            "circuitType": "transfer-confidential", "nInputs": 1, "nOutputs": 2,
            "inputs": [input],
            "outputs": [["utxo": utxo, "isDummy": "0x0", "hash": "0x41", "ownerPkHash": "0x31", "nullifierPk": "0x51"],
                        ["utxo": padding, "isDummy": "0x1", "hash": "0x42", "ownerPkHash": "0x32", "nullifierPk": "0x0"]]
                as [[String: AnyHashable]],
            "treeSlots": [["id": "0x0", "utxoRoot": "0x71", "nullifierRoot": "0x72"], unused, unused, unused, unused],
            "outputTreeId": "0x1a", "blindingSeed": "0xd1", "externalDataHash": "0x61", "privateTxHash": "0x62",
            "publicAssets": ["0x0", "0x0", "0x0"], "publicAmounts": ["0x0", "0x0", "0x0"], "ringProgramId": "0x0",
            "signerPkHashes": ["0x31", "0x0"], "inputFlags": "0x1", "publishedOutputOwnerPkHashes": ["0x31", "0x32"],
            "cacheTreeId": "0x0", "cacheReadHashChain": "0x0", "cacheReadHashes": [String](), "cacheIsCached": [String](),
            "cacheReadIndex": [String](), "publicInputHash": "0x99",
        ])
    }

    @Test
    func `Inputs without an inclusion proof send a zero state path`() throws {
        let request = try TransferProofRequest(treeSlots: [Fixture.treeSlot()], publicInputHash: Fixture.field(0x99),
                                               witness: Fixture.witness(isDummy: true, hasInclusionProof: false))

        let input = try #require((try json(request)["inputs"] as? [[String: AnyHashable]])?.first)

        #expect(input["statePathElements"] as? [String] == Array(repeating: "0x0", count: 32))
        #expect(input["statePathIndex"] as? String == "0x0")
        #expect(input["nullifierLowPathIndex"] as? String == "0x9")
        #expect(input["isDummy"] as? String == "0x1")
    }

    @Test
    func `Read cache entries encode as hexadecimal`() throws {
        let cached = try Fixture.witness(hasInclusionProof: false, cacheTreeID: Fixture.field(2),
                                         cacheReadHashes: [Fixture.field(4)], cacheIsCached: [true], cacheReadIndexes: [0])

        let body = try json(TransferProofRequest(treeSlots: [Fixture.treeSlot()], publicInputHash: Fixture.field(1),
                                                 witness: cached))

        #expect(body["cacheTreeId"] as? String == "0x2")
        #expect(body["cacheReadHashes"] as? [String] == ["0x4"])
        #expect(body["cacheIsCached"] as? [String] == ["0x1"])
        #expect(body["cacheReadIndex"] as? [String] == ["0x0"])
    }

    private func json(_ request: TransferProofRequest) throws -> [String: AnyHashable] {
        try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(TransferProofBody(request))) as? [String: AnyHashable])
    }
}
