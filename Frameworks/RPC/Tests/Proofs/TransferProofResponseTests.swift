import Foundation
import Testing
@testable import RPC

/// Verifies the strict decoding of a prover's proof on the complete route.
struct TransferProofResponseTests {
    private typealias Fixture = ProofFixtures

    /// Verifies coordinates, `b`'s word order, and the digest, from padded and unpadded text.
    ///
    /// - Throws: A decoding error, or a failed test prerequisite.
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

    /// Verifies a proof without a valid digest fails to decode: missing, uppercase, short, or not hexadecimal.
    ///
    /// - Parameter digest: The digest member, or `nil` to omit it.
    @Test(arguments: [
        String?.none,
        String(repeating: "7E", count: 32),
        String(repeating: "7e", count: 31),
        String(repeating: "7g", count: 32),
    ])
    func `Proofs without a valid digest fail`(digest: String?) {
        #expect(throws: DecodingError.self) { try decode(Fixture.response(digest: digest)) }
    }

    /// Verifies a proof with a commitment, which only P-256 proofs carry, fails to decode.
    ///
    /// - Parameter field: The commitment field.
    @Test(arguments: ["proofCommitment", "proofCommitmentPok"])
    func `Proofs with a commitment fail`(field: String) {
        let json = Fixture.response().replacingOccurrences(
            of: #""krs":"#, with: #""\#(field)":[\#(ProofFixtures.word(1)),\#(ProofFixtures.word(2))],"krs":"#
        )

        #expect(throws: DecodingError.self) { try decode(json) }
    }

    /// Verifies malformed points fail to decode: a word over 32 bytes, a word without `0x`, and a missing word.
    ///
    /// - Parameters:
    ///   - field: The JSON text to replace.
    ///   - replacement: The malformed text.
    /// - Throws: A failed test prerequisite.
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

    /// Decodes a response body.
    /// - Parameter json: The body's text.
    /// - Returns: The decoded response.
    /// - Throws: A decoding error.
    private func decode(_ json: String) throws -> TransferProofResponse {
        try JSONDecoder().decode(TransferProofResponse.self, from: Data(json.utf8))
    }
}
