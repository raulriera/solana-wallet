import Foundation
import Testing
@testable import RPC

struct IndexedTransferProofBodyTests {
    private typealias Fixture = ProofFixtures

    private static let pathKeys: Set = [
        "statePathElements", "statePathIndex", "nullifierLowValue", "nullifierNextValue", "nullifierLowPathElements",
        "nullifierLowPathIndex",
    ]

    @Test
    func `The envelope sends base 58 trees and commitments, null padding commitments, and prover hex public inputs`()
        throws {
        let request = try Fixture.twoTreeRequest(
            publicInputs: Fixture.publicInputs(replacing: 16, with: Fixture.field(0x85))
        )

        let body = try Fixture.json(IndexedTransferProofBody(request))

        #expect(Set(body.keys) == ["circuitType", "prepared", "trees", "inputs", "publicInputs"])
        #expect(body["circuitType"] as? String == "transfer-confidential")
        #expect(body["trees"] as? [[String: AnyHashable]] == [
            ["tree": Fixture.tree, "id": 0], ["tree": Fixture.zeroAddress, "id": 7],
        ])
        #expect(body["inputs"] as? [[String: AnyHashable]] == [
            ["treeSlot": 0, "commitment": String(repeating: "1", count: 31) + "4t"],
            ["treeSlot": 1, "commitment": String(repeating: "1", count: 31) + "4u"],
            ["treeSlot": 0, "commitment": NSNull()],
        ])
        #expect(body["publicInputs"] as? [String] == [
            "0x81", "0x82", "0x1a", "0x62", "0x61", "0x0", "0x0", "0x0", "0x0", "0x0", "0x0", "0x0", "0x83", "0x1",
            "0x84", "0x0", "0x85",
        ])
        #expect((body["prepared"] as? [String: AnyHashable])?["cacheReadHashChain"] as? String == "0x85")
    }

    @Test
    func `The prepared witness is the complete route's body without tree slots, paths, or a public input hash`()
        throws {
        let prepared = try #require(
            try Fixture.json(IndexedTransferProofBody(Fixture.indexedRequest()))["prepared"] as? [String: AnyHashable]
        )
        var complete = try Fixture.json(TransferProofBody(Fixture.request()))
        let completeInputs = try #require(complete["inputs"] as? [[String: AnyHashable]])
        complete["treeSlots"] = nil
        complete["publicInputHash"] = nil
        complete["inputs"] = completeInputs.map { $0.filter { !Self.pathKeys.contains($0.key) } }

        #expect(prepared == complete)
    }
}
