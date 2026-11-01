import Encoding
import Foundation
import ModularArithmetic
import Testing
@testable import Privacy
@testable import RPC

enum IndexedProofs {
    static let utxoRootIndex: UInt16 = 31

    static let nullifierRootIndex: UInt16 = 87

    private static let utxoRoot = Poseidon.Element(UInt64(0x71))

    private static let nullifierRoot = Poseidon.Element(UInt64(0x72))

    static func prover() throws -> StubProver {
        try StubProver(answer: answer(to:))
    }

    static func proof(for shape: Shape) -> TransferProof {
        let point = TransferProof.G1Point(x: field(1), y: field(2))
        return TransferProof(a: point, b: field(1) + field(2) + field(1) + field(2), c: point,
                             provingKeyDigest: shape.provingKeyDigest)
    }

    private static func answer(to body: Data) throws -> (status: Int, body: String) {
        let request = try JSONDecoder().decode(Request.self, from: body)
        let elements = try request.publicInputs.map { try #require(FieldHex.decode($0).flatMap(Poseidon.Element.init)) }
        let slots = request.trees.map {
            PublicInputs.TreeSlot(treeID: $0.id, utxoRoot: utxoRoot, nullifierRoot: nullifierRoot)
        }
        let hash = PublicInputs.hash(elements: elements, treeSlots: slots)
        let proof = proof(for: Shape(inputs: request.prepared.nInputs, outputs: request.prepared.nOutputs))
        let words = stride(from: 0, to: proof.b.count, by: 32).map { FieldHex.encode(Array(proof.b[$0..<$0 + 32])) }
        let trees: [[String: Any]] = request.trees.map {
            ["tree": $0.tree, "id": $0.id, "utxoRoot": FieldHex.encode(utxoRoot.bigEndianBytes),
             "nullifierRoot": FieldHex.encode(nullifierRoot.bigEndianBytes), "utxoRootIndex": utxoRootIndex,
             "nullifierRootIndex": nullifierRootIndex]
        }
        let answer: [String: Any] = [
            "ar": [FieldHex.encode(proof.a.x), FieldHex.encode(proof.a.y)],
            "bs": [Array(words[0..<2]), Array(words[2..<4])],
            "krs": [FieldHex.encode(proof.c.x), FieldHex.encode(proof.c.y)],
            "provingKeySha256": Hex.encode(proof.provingKeyDigest),
            "resolution": [
                "trees": trees,
                "publicInputHash": FieldHex.encode(hash.bigEndianBytes),
            ] as [String: Any],
        ]
        return (200, String(decoding: try JSONSerialization.data(withJSONObject: answer), as: UTF8.self))
    }

    private static func field(_ value: UInt8) -> [UInt8] { Array(repeating: 0, count: 31) + [value] }
}

private struct Request: Decodable {
    struct Prepared: Decodable {
        let nInputs: Int
        let nOutputs: Int
    }

    struct Tree: Decodable {
        let tree: String
        let id: UInt16
    }

    let prepared: Prepared
    let trees: [Tree]
    let publicInputs: [String]
}
