import Foundation
import Testing
@testable import RPC

struct TransferProofResponseTests {
    private typealias Fixture = ProofFixtures

    @Test
    func `Proofs decode their points and digest`() throws {
        let unpadded = Fixture.response().replacingOccurrences(of: Fixture.word(8), with: #""0x8""#)

        let proof = try decode(unpadded).proof

        #expect(proof == TransferProof(
            a: .init(x: Fixture.field(1), y: Fixture.field(2)),
            b: Fixture.field(3) + Fixture.field(4) + Fixture.field(5) + Fixture.field(6),
            c: .init(x: Fixture.field(7), y: Fixture.field(8)),
            provingKeyDigest: Array(repeating: 0x7e, count: 32)
        ))
    }

    @Test(arguments: [
        String?.none,
        String(repeating: "7E", count: 32),
        String(repeating: "7e", count: 31),
        String(repeating: "7g", count: 32),
    ])
    func `Proofs without a valid digest fail`(digest: String?) {
        #expect(throws: DecodingError.self) { try decode(Fixture.response(digest: digest)) }
    }

    @Test(arguments: ["proofCommitment", "proofCommitmentPok"])
    func `Proofs with a commitment fail`(field: String) {
        let json = Fixture.response().replacingOccurrences(
            of: #""krs":"#, with: #""\#(field)":[\#(ProofFixtures.word(1)),\#(ProofFixtures.word(2))],"krs":"#
        )

        #expect(throws: DecodingError.self) { try decode(json) }
    }

    @Test(arguments: [
        (ProofFixtures.word(1), "\"0x1" + String(repeating: "0", count: 64) + "\""),
        (ProofFixtures.word(8), #""8""#),
        (ProofFixtures.word(5) + ",", ""),
    ] as [(String, String)])
    func `Malformed points fail`(field: String, replacement: String) throws {
        let valid = Fixture.response()
        try #require(valid.contains(field))

        #expect(throws: DecodingError.self) { try decode(valid.replacingOccurrences(of: field, with: replacement)) }
    }

    private func decode(_ json: String) throws -> TransferProofResponse {
        try JSONDecoder().decode(TransferProofResponse.self, from: Data(json.utf8))
    }
}
