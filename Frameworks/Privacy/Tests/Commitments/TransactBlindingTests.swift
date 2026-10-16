import ModularArithmetic
@testable import Privacy
import Testing

/// Verifies the transact blinding derivations against zolana's published blinding-seed vector and
/// transfers, and against independently derived values.
///
/// The vector's first nullifier is 7 and its blinding seed is 42. The transfers' output blindings
/// are checked through their output commitments in ``UTXOTests``.
struct TransactBlindingTests {
    /// The published blinding-seed vector.
    private let vector: CommitmentVectors.BlindingSeed

    /// Reads the published blinding-seed vector from the fixture.
    ///
    /// - Throws: A test failure if the fixture is missing, or an error if it can't be read or decoded.
    init() throws {
        vector = try CommitmentVectors.load().blindingSeed
    }

    /// Verifies the output blinding seed against the published value.
    @Test
    func `Output blinding seeds match the published vector`() throws {
        let seed = TransactBlinding.outputBlindingSeed(
            firstNullifier: Poseidon.Element(vector.firstNullifier), blindingSeed: Poseidon.Element(vector.blindingSeed)
        )

        #expect(seed.bigEndianBytes == (try fixtureBytes(vector.outputBlindingSeed)))
    }

    /// Verifies the private transaction blinding against the published value.
    @Test
    func `Private transaction blindings match the published vector`() throws {
        let blinding = TransactBlinding.privateTransactionBlinding(
            firstNullifier: Poseidon.Element(vector.firstNullifier), blindingSeed: Poseidon.Element(vector.blindingSeed)
        )

        #expect(blinding.bigEndianBytes == (try fixtureBytes(vector.privateTxBlinding)))
    }

    /// Verifies private transaction blindings against zolana's published transfers.
    ///
    /// Each proof's first nullifier and blinding seed are 32-byte values, unlike the small integers
    /// of the blinding-seed vector.
    ///
    /// - Parameter proof: A published first nullifier and its private transaction blinding.
    @Test(arguments: TransferVectors.proofs)
    func `Private transaction blindings match the published transfers`(_ proof: TransferVectors.Proof) throws {
        let blinding = TransactBlinding.privateTransactionBlinding(
            firstNullifier: try Poseidon.Element(hex: proof.firstNullifier), blindingSeed: TransferVectors.blindingSeed
        )

        #expect(blinding.bigEndianBytes == (try fixtureBytes(proof.privateTransactionBlinding)))
    }

    /// Verifies output blindings against both published values for the vector's slot.
    ///
    /// The protocol derives an output blinding from the published output blinding seed. zolana also
    /// publishes the derivation applied to the blinding seed itself, which checks the hash alone.
    ///
    /// - Parameters:
    ///   - outputBlindingSeed: The seed that the derivation hashes.
    ///   - hex: The published output blinding.
    @Test(arguments: try TransactBlindingTests.publishedOutputBlindings())
    func `Output blindings match the published vectors`(outputBlindingSeed: Poseidon.Element, hex: String) throws {
        let blinding = TransactBlinding.outputBlinding(
            firstNullifier: Poseidon.Element(vector.firstNullifier), outputBlindingSeed: outputBlindingSeed, index: vector.outputIndex
        )

        #expect(blinding.bigEndianBytes == (try fixtureBytes(hex)))
    }

    /// Verifies the output blindings of the first and last slot indices against independently
    /// derived values.
    ///
    /// The values come from a separate Python implementation of Poseidon, with the published first
    /// nullifier and output blinding seed.
    ///
    /// - Parameters:
    ///   - index: An output slot index.
    ///   - hex: The expected output blinding.
    @Test(arguments: [
        (0, "299898f230b61b7407cfc381134b75c628f6a678b66e8048806e0a98d2310e10"),
        (.max, "17c346af36647c27e9ec8047ace9ac25ca5b56dda2d3401b0f3a6a54df9932ca"),
    ] as [(UInt32, String)])
    func `Output blindings at the first and last index match independently derived values`(index: UInt32, hex: String) throws {
        let blinding = TransactBlinding.outputBlinding(
            firstNullifier: Poseidon.Element(vector.firstNullifier), outputBlindingSeed: try Poseidon.Element(hex: vector.outputBlindingSeed), index: index
        )

        #expect(blinding.bigEndianBytes == (try fixtureBytes(hex)))
    }

    /// Pairs each seed in the published blinding-seed vector with the output blinding derived from
    /// it.
    ///
    /// - Returns: The output blinding seed with the derived output blinding, then the blinding seed
    ///   with the direct output blinding.
    /// - Throws: A test failure if the fixture is missing or malformed, or an error if it can't be
    ///   read or decoded.
    private static func publishedOutputBlindings() throws -> [(Poseidon.Element, String)] {
        let vector = try CommitmentVectors.load().blindingSeed
        return [
            (try Poseidon.Element(hex: vector.outputBlindingSeed), vector.derivedOutputBlinding),
            (Poseidon.Element(vector.blindingSeed), vector.directOutputBlinding),
        ]
    }
}
