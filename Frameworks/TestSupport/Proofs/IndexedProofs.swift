import Algorithms
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
        let point = TransferProof.G1Point(x: fieldElement(1), y: fieldElement(2))
        return TransferProof(a: point, b: fieldElement(1) + fieldElement(2) + fieldElement(1) + fieldElement(2),
                             c: point, provingKeyDigest: shape.provingKeyDigest)
    }

    private static func answer(to body: Data) throws -> (status: Int, body: String) {
        let request = try JSONDecoder().decode(Request.self, from: body)
        let elements = try request.publicInputs.map { try #require(FieldHex.decode($0).flatMap(Poseidon.Element.init)) }
        let slots = request.trees.map {
            PublicInputs.TreeSlot(treeID: $0.id, utxoRoot: utxoRoot, nullifierRoot: nullifierRoot)
        }
        let hash = PublicInputs.hash(elements: elements, treeSlots: slots)
        let proof = proof(for: Shape(inputs: request.prepared.nInputs, outputs: request.prepared.nOutputs))
        let words = proof.b.chunks(ofCount: 32).map { ProverAnswer.word(Array($0)) }
        let trees = request.trees.map {
            ProverAnswer.tree(
                tree: .string($0.tree), id: .number(Double($0.id)),
                utxoRoot: ProverAnswer.word(utxoRoot.bigEndianBytes),
                nullifierRoot: ProverAnswer.word(nullifierRoot.bigEndianBytes),
                utxoRootIndex: .number(Double(utxoRootIndex)), nullifierRootIndex: .number(Double(nullifierRootIndex))
            )
        }
        let answer = try ProverAnswer.indexed(
            proof: ProverAnswer.proof(
                a: [ProverAnswer.word(proof.a.x), ProverAnswer.word(proof.a.y)],
                b: [.array(Array(words[0..<2])), .array(Array(words[2..<4]))],
                c: [ProverAnswer.word(proof.c.x), ProverAnswer.word(proof.c.y)],
                digest: .string(Hex.encode(proof.provingKeyDigest))
            ),
            trees: .array(trees),
            publicInputHash: ProverAnswer.word(hash.bigEndianBytes)
        )
        return (200, try answer.json)
    }
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
