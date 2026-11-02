import Foundation
import Testing
@testable import RPC

struct IndexedTransferProofResponseTests {
    private typealias Fixture = ProofFixtures

    @Test(arguments: ["0x71", ProverAnswer.word(0x71)] as [JSONValue])
    func `A resolution decodes its trees and public input hash`(utxoRoot: JSONValue) throws {
        let json = try ProverAnswer.indexed(
            trees: [ProverAnswer.tree(tree: .string(ProverAnswer.zeroAddress), id: 65535, utxoRoot: utxoRoot,
                                      utxoRootIndex: 499, nullifierRootIndex: 0)],
            publicInputHash: ProverAnswer.word(fixtureBytes(Fixture.fieldOrderMinusOne))
        )

        let resolution = try decode(json).proof.resolution

        #expect(resolution == ProofResolution(
            trees: [.init(id: 65535, address: fieldElement(0), utxoRoot: fieldElement(0x71),
                          nullifierRoot: fieldElement(0x72), utxoRootIndex: 499, nullifierRootIndex: 0)],
            publicInputHash: try fixtureBytes(Fixture.fieldOrderMinusOne)
        ))
    }

    @Test(arguments: [
        ProverAnswer.tree(tree: "0OIl0OIl0OIl0OIl0OIl0OIl0OIl0OIl"),
        ProverAnswer.tree(tree: .string(String(repeating: "1", count: 31))),
        ProverAnswer.tree(tree: 7),
        ProverAnswer.tree(id: -1),
        ProverAnswer.tree(id: 65536),
        ProverAnswer.tree(id: "0"),
        ProverAnswer.tree(id: 1.5),
        ProverAnswer.tree(utxoRootIndex: 65536),
        ProverAnswer.tree(nullifierRootIndex: -1),
    ])
    func `Trees with a malformed address, ID, or root index are refused`(tree: JSONValue) throws {
        let json = try ProverAnswer.indexed(trees: [tree])

        #expect(throws: DecodingError.self) { try decode(json) }
    }

    @Test(arguments: ["utxoRoot", "nullifierRoot", "publicInputHash"], [
        "0xAB",
        .string("0x" + String(repeating: "0", count: 64) + "1"),
        .string("0x" + ProofFixtures.fieldOrder),
        "71",
        "0x",
        113,
    ] as [JSONValue])
    func `Roots and hashes that aren't canonical lowercase prover hex are refused`(field: String, value: JSONValue)
        throws {
        let json =
            switch field {
            case "utxoRoot": try ProverAnswer.indexed(trees: [ProverAnswer.tree(utxoRoot: value)])
            case "nullifierRoot": try ProverAnswer.indexed(trees: [ProverAnswer.tree(nullifierRoot: value)])
            default: try ProverAnswer.indexed(publicInputHash: value)
            }

        #expect(throws: DecodingError.self) { try decode(json) }
    }

    @Test(arguments: try [
        ProverAnswer.proof(),
        ProverAnswer.indexed(publicInputHash: nil),
        ProverAnswer.indexed(trees: nil),
    ])
    func `Proofs without a whole resolution are refused`(json: JSONValue) {
        #expect(throws: DecodingError.self) { try decode(json) }
    }

    private func decode(_ json: JSONValue) throws -> IndexedTransferProofResponse {
        try JSONDecoder().decode(IndexedTransferProofResponse.self, from: json.data)
    }
}
