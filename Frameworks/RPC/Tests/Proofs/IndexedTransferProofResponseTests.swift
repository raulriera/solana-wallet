import Foundation
import Testing
@testable import RPC

struct IndexedTransferProofResponseTests {
    private typealias Fixture = ProofFixtures

    @Test(arguments: [#""0x71""#, ProofFixtures.word(0x71)])
    func `A resolution decodes its trees and public input hash`(utxoRoot: String) throws {
        let json = Fixture.indexedResponse(
            trees: [Fixture.resolvedTree(tree: #""\#(Fixture.zeroAddress)""#, id: "65535", utxoRoot: utxoRoot,
                                         utxoRootIndex: "499", nullifierRootIndex: "0")],
            publicInputHash: #""0x\#(Fixture.fieldOrderMinusOne)""#
        )

        let resolution = try decode(json).proof.resolution

        #expect(resolution == ProofResolution(
            trees: [.init(id: 65535, address: Fixture.zeroBytes, utxoRoot: Fixture.field(0x71),
                          nullifierRoot: Fixture.field(0x72), utxoRootIndex: 499, nullifierRootIndex: 0)],
            publicInputHash: try fixtureBytes(Fixture.fieldOrderMinusOne)
        ))
    }

    @Test(arguments: [
        ProofFixtures.resolvedTree(tree: #""0OIl0OIl0OIl0OIl0OIl0OIl0OIl0OIl""#),
        ProofFixtures.resolvedTree(tree: #""\#(String(repeating: "1", count: 31))""#),
        ProofFixtures.resolvedTree(tree: "7"),
        ProofFixtures.resolvedTree(id: "-1"),
        ProofFixtures.resolvedTree(id: "65536"),
        ProofFixtures.resolvedTree(id: #""0""#),
        ProofFixtures.resolvedTree(id: "1.5"),
        ProofFixtures.resolvedTree(utxoRootIndex: "65536"),
        ProofFixtures.resolvedTree(nullifierRootIndex: "-1"),
    ])
    func `Trees with a malformed address, ID, or root index are refused`(tree: String) {
        #expect(throws: DecodingError.self) { try decode(Fixture.indexedResponse(trees: [tree])) }
    }

    @Test(arguments: ["utxoRoot", "nullifierRoot", "publicInputHash"], [
        #""0xAB""#,
        #""0x\#(String(repeating: "0", count: 64))1""#,
        #""0x\#(ProofFixtures.fieldOrder)""#,
        #""71""#,
        #""0x""#,
        "113",
    ])
    func `Roots and hashes that aren't canonical lowercase prover hex are refused`(field: String, value: String) {
        let json =
            switch field {
            case "utxoRoot": Fixture.indexedResponse(trees: [Fixture.resolvedTree(utxoRoot: value)])
            case "nullifierRoot": Fixture.indexedResponse(trees: [Fixture.resolvedTree(nullifierRoot: value)])
            default: Fixture.indexedResponse(publicInputHash: value)
            }

        #expect(throws: DecodingError.self) { try decode(json) }
    }

    @Test(arguments: [
        ProofFixtures.response(),
        ProofFixtures.indexedResponse().replacingOccurrences(of: #","publicInputHash":"#, with: #","other":"#),
        ProofFixtures.indexedResponse().replacingOccurrences(of: #""trees":"#, with: #""other":"#),
    ])
    func `Proofs without a whole resolution are refused`(json: String) {
        #expect(throws: DecodingError.self) { try decode(json) }
    }

    private func decode(_ json: String) throws -> IndexedTransferProofResponse {
        try JSONDecoder().decode(IndexedTransferProofResponse.self, from: Data(json.utf8))
    }
}
