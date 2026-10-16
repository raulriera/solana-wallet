import Foundation
import Testing
@testable import RPC

/// Verifies the JSON body of a transfer proof request on the indexed route.
struct TransferProofBodyTests {
    private typealias Fixture = ProofFixtures

    /// Verifies the lookup envelope: trees, base-58 commitments with explicit `null`, hexadecimal public
    /// inputs, and the minimum slot.
    ///
    /// - Throws: An encoding or parsing error, or a failed test prerequisite.
    @Test
    func `The envelope lists trees lookups and public inputs`() throws {
        let body = try json(Fixture.request())

        #expect(body["circuitType"] as? String == "transfer-confidential")
        #expect(body["trees"] as? [[String: AnyHashable]] == [["tree": Fixture.tree, "id": 0]])
        #expect(body["inputs"] as? [[String: AnyHashable]] == [[
            "treeSlot": 0, "commitment": "JEKNVnkbo3jma5nREBBJCDoXFVeKkD56V3xKrvRmWxFG", "nullifier": NSNull(),
        ]])
        #expect(body["publicInputs"] as? [String] == (1...17).map { "0x" + String($0, radix: 16) })
        #expect(body["minContextSlot"] as? Int == 99)
    }

    /// Verifies a request without a minimum slot omits the field.
    ///
    /// - Throws: An encoding or parsing error, or a failed test prerequisite.
    @Test
    func `Requests without a minimum slot omit it`() throws {
        let request = try Fixture.request()
        let body = try json(try TransferProofRequest(trees: request.trees, inputs: request.inputs,
                                                     publicInputs: request.publicInputs, minContextSlot: nil,
                                                     witness: request.witness))

        #expect(body.keys.sorted() == ["circuitType", "inputs", "prepared", "publicInputs", "trees"])
    }

    /// Verifies the prepared witness writes every field as zolana's `prepared` object does.
    ///
    /// - Throws: An encoding or parsing error, or a failed test prerequisite.
    @Test
    func `The prepared witness matches zolana's fields`() throws {
        let prepared = try #require(try json(Fixture.request())["prepared"] as? [String: AnyHashable])

        let utxo = ["domain": "0x3", "owner": "0x11", "asset": "0x0", "amount": "0xa1", "blinding": "0xb1",
                    "dataHash": "0x0", "ringDataHash": "0x0", "ringProgramId": "0x0"]
        let padding = utxo.merging(["domain": "0x1"]) { $1 }
        #expect(prepared == [
            "circuitType": "transfer-confidential", "nInputs": 1, "nOutputs": 2,
            "inputs": [["utxo": utxo, "isDummy": "0x0", "treeSlot": "0x0", "nullifier": "0x21",
                        "ownerPkHash": "0x31", "nullifierSecret": "0xc1"]] as [[String: AnyHashable]],
            "outputs": [["utxo": utxo, "isDummy": "0x0", "hash": "0x41", "ownerPkHash": "0x31", "nullifierPk": "0x51"],
                        ["utxo": padding, "isDummy": "0x1", "hash": "0x42", "ownerPkHash": "0x32", "nullifierPk": "0x0"]]
                as [[String: AnyHashable]],
            "outputTreeId": "0x1a", "blindingSeed": "0xd1", "externalDataHash": "0x61", "privateTxHash": "0x62",
            "publicAssets": ["0x0", "0x0", "0x0"], "publicAmounts": ["0x0", "0x0", "0x0"], "ringProgramId": "0x0",
            "signerPkHashes": ["0x31", "0x0"], "inputFlags": "0x1", "publishedOutputOwnerPkHashes": ["0x31", "0x32"],
            "cacheTreeId": "0x0", "cacheReadHashChain": "0x0", "cacheReadHashes": [String](), "cacheIsCached": [String](),
            "cacheReadIndex": [String](),
        ])
    }

    /// Verifies read-cache entries encode as hexadecimal, with flags as `0x0` or `0x1`.
    ///
    /// - Throws: An encoding or parsing error, or a failed test prerequisite.
    @Test
    func `Read cache entries encode as hexadecimal`() throws {
        let cached = try Fixture.witness(cacheTreeID: Fixture.field(2), cacheReadHashes: [Fixture.field(4)],
                                         cacheIsCached: [true], cacheReadIndexes: [0])

        let prepared = try #require(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(TransferProofBody.Prepared(cached))) as? [String: Any])

        #expect(prepared["cacheTreeId"] as? String == "0x2")
        #expect(prepared["cacheReadHashes"] as? [String] == ["0x4"])
        #expect(prepared["cacheIsCached"] as? [String] == ["0x1"])
        #expect(prepared["cacheReadIndex"] as? [String] == ["0x0"])
    }

    /// Encodes a request's body as a JSON object.
    /// - Parameter request: The request.
    /// - Returns: The body's object.
    /// - Throws: An encoding or parsing error, or a failed test prerequisite.
    private func json(_ request: TransferProofRequest) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(TransferProofBody(request))) as? [String: Any])
    }
}
