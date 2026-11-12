import ModularArithmetic
import Testing
@testable import Privacy

struct TransactBlindingTests {
    private let vector: CommitmentVectors.BlindingSeed

    init() throws {
        vector = try CommitmentVectors.load().blindingSeed
    }

    @Test
    func `Output blinding seeds match the published vector`() throws {
        let seed = TransactBlinding.outputBlindingSeed(
            firstNullifier: Poseidon.Element(vector.firstNullifier), blindingSeed: Poseidon.Element(vector.blindingSeed)
        )

        #expect(seed.bigEndianBytes == (try fixtureBytes(vector.outputBlindingSeed)))
    }

    @Test
    func `Private transaction blindings match the published vector`() throws {
        let blinding = TransactBlinding.privateTransactionBlinding(
            firstNullifier: Poseidon.Element(vector.firstNullifier), blindingSeed: Poseidon.Element(vector.blindingSeed)
        )

        #expect(blinding.bigEndianBytes == (try fixtureBytes(vector.privateTxBlinding)))
    }

    @Test(arguments: TransferVectors.proofs)
    func `Private transaction blindings match the published transfers`(_ proof: TransferVectors.Proof) throws {
        let blinding = TransactBlinding.privateTransactionBlinding(
            firstNullifier: try Poseidon.Element(hex: proof.firstNullifier), blindingSeed: TransferVectors.blindingSeed
        )

        #expect(blinding.bigEndianBytes == (try fixtureBytes(proof.privateTransactionBlinding)))
    }

    @Test(arguments: try TransactBlindingTests.publishedOutputBlindings())
    func `Output blindings match the published vectors`(outputBlindingSeed: Poseidon.Element, hex: String) throws {
        let blinding = TransactBlinding.outputBlinding(
            firstNullifier: Poseidon.Element(vector.firstNullifier), outputBlindingSeed: outputBlindingSeed, index: vector.outputIndex
        )

        #expect(blinding.bigEndianBytes == (try fixtureBytes(hex)))
    }

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

    private static func publishedOutputBlindings() throws -> [(Poseidon.Element, String)] {
        let vector = try CommitmentVectors.load().blindingSeed
        return [
            (try Poseidon.Element(hex: vector.outputBlindingSeed), vector.derivedOutputBlinding),
            (Poseidon.Element(vector.blindingSeed), vector.directOutputBlinding),
        ]
    }
}
