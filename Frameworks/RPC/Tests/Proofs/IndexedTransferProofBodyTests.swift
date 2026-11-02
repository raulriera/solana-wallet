import Foundation
import Testing
@testable import RPC

struct IndexedTransferProofBodyTests {
    private typealias Fixture = ProofFixtures

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
}
