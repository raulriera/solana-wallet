import Foundation
import Testing
@testable import RPC

/// Verifies the strict decoding of a prover's proof and resolution.
struct TransferProofResponseTests {
    private typealias Fixture = ProofFixtures

    /// Verifies coordinates, `b`'s word order, the digest, and the resolution, from padded and unpadded text.
    ///
    /// - Throws: A decoding error, or a failed test prerequisite.
    @Test
    func `Proofs decode their points digest and resolution`() throws {
        let proof = try decode(Fixture.response()).proof

        #expect(proof == TransferProof(
            a: .init(x: Fixture.field(1), y: Fixture.field(2)),
            b: Fixture.field(3) + Fixture.field(4) + Fixture.field(5) + Fixture.field(6),
            c: .init(x: Fixture.field(7), y: Fixture.field(8)),
            provingKeyDigest: Array(repeating: 0x7e, count: 32),
            resolution: .init(trees: [.init(address: Fixture.tree, id: 0, utxoRoot: Fixture.field(10),
                                            nullifierRoot: Fixture.field(11), utxoRootIndex: 499, nullifierRootIndex: 7)],
                              publicInputHash: Array(repeating: 0, count: 30) + [0x01, 0x23])
        ))
    }

    /// Verifies a proof without its digest or resolution, which this route requires, fails to decode.
    ///
    /// - Parameters:
    ///   - digest: The digest member, or `nil` to omit it.
    ///   - resolution: Whether to include the resolution.
    @Test(arguments: [
        (String?.none, true),
        (String(repeating: "7E", count: 32), true),
        (String(repeating: "7e", count: 31), true),
        (String(repeating: "7g", count: 32), true),
        (String(repeating: "7e", count: 32), false),
    ])
    func `Proofs without a valid digest or resolution fail`(digest: String?, resolution: Bool) {
        #expect(throws: DecodingError.self) { try decode(Fixture.response(digest: digest, resolution: resolution)) }
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

    /// Verifies malformed points and trees fail to decode.
    ///
    /// - Parameters:
    ///   - field: The JSON text to replace.
    ///   - replacement: The malformed text.
    /// - Throws: A failed test prerequisite.
    @Test(arguments: [
        (ProofFixtures.word(1), "\"0x1" + String(repeating: "0", count: 64) + "\""),
        (ProofFixtures.word(8), #""8""#),
        (ProofFixtures.word(5) + ",", ""),
        (#""tree":"33KVhbT4QtdQDrrrGwwThqD47Dh4Q6tA443t9jMNcWFN""#, #""tree":"3QJmV3qfvL9SuYo34YihAf3sRCW3qSinyC""#),
        (#""utxoRootIndex":499"#, #""utxoRootIndex":65536"#),
    ] as [(String, String)])
    func `Malformed points and trees fail`(field: String, replacement: String) throws {
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
