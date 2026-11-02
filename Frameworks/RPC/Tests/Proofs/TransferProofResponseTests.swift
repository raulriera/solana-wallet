import Foundation
import Testing
@testable import RPC

struct TransferProofResponseTests {
    @Test
    func `Proofs decode their points and digest`() throws {
        let unpadded = ProverAnswer.proof(c: [ProverAnswer.word(7), "0x8"])

        let proof = try decode(unpadded).proof

        #expect(proof == TransferProof(
            a: .init(x: fieldElement(1), y: fieldElement(2)),
            b: fieldElement(3) + fieldElement(4) + fieldElement(5) + fieldElement(6),
            c: .init(x: fieldElement(7), y: fieldElement(8)),
            provingKeyDigest: Array(repeating: 0x7e, count: 32)
        ))
    }

    @Test(arguments: [
        nil,
        .string(String(repeating: "7E", count: 32)),
        .string(String(repeating: "7e", count: 31)),
        .string(String(repeating: "7g", count: 32)),
    ] as [JSONValue?])
    func `Proofs without a valid digest fail`(digest: JSONValue?) {
        #expect(throws: DecodingError.self) { try decode(ProverAnswer.proof(digest: digest)) }
    }

    @Test(arguments: ["proofCommitment", "proofCommitmentPok"])
    func `Proofs with a commitment fail`(field: String) throws {
        var members = try #require(ProverAnswer.proof().members)
        members[field] = [ProverAnswer.word(1), ProverAnswer.word(2)]

        #expect(throws: DecodingError.self) { try decode(.object(members)) }
    }

    @Test(arguments: [
        ProverAnswer.proof(a: [.string("0x1" + String(repeating: "0", count: 64)), ProverAnswer.word(2)]),
        ProverAnswer.proof(c: [ProverAnswer.word(7), "8"]),
        ProverAnswer.proof(b: [[ProverAnswer.word(3), ProverAnswer.word(4)], [ProverAnswer.word(6)]]),
    ])
    func `Malformed points fail`(proof: JSONValue) {
        #expect(throws: DecodingError.self) { try decode(proof) }
    }

    private func decode(_ json: JSONValue) throws -> TransferProofResponse {
        try JSONDecoder().decode(TransferProofResponse.self, from: json.data)
    }
}
