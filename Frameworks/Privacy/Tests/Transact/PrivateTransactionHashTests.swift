import ModularArithmetic
@testable import Privacy
import Testing

/// Verifies the nonzero hash chain and the private transaction hash against zolana's published
/// vectors and transfers.
struct PrivateTransactionHashTests {
    /// Verifies every published chain, including empty and all-zero lists, padding at each position,
    /// reversed order, and r - 1.
    ///
    /// - Parameter vector: A published chain.
    @Test(arguments: try NonzeroHashChainVectors.load().vectors)
    func `Chains match the published vectors`(_ vector: NonzeroHashChainVectors.Chain) throws {
        let elements = try vector.inputs.map { try Poseidon.Element(hex: $0) }

        #expect(PrivateTransactionHash.nonzeroChain(elements).bigEndianBytes == (try fixtureBytes(vector.output)))
    }

    /// Verifies the published hashes of transacts that create no address: padding at different
    /// positions, two inputs, and reordered inputs.
    ///
    /// - Parameter vector: A published hash whose address nullifiers are all zero.
    @Test(arguments: try PrivateTransactionHashVectors.load().vectors.filter(\.createsNoAddress))
    func `Hashes match the published vectors`(_ vector: PrivateTransactionHashVectors.Hash) throws {
        let hash = PrivateTransactionHash.hash(
            inputs: try vector.inputHashes.map { try Poseidon.Element(hex: $0) },
            outputs: try vector.outputHashes.map { try Poseidon.Element(hex: $0) },
            blinding: try Poseidon.Element(hex: vector.blinding)
        )

        #expect(hash.bigEndianBytes == (try fixtureBytes(vector.privateTransactionHash)))
    }

    /// Verifies that the published vectors without addresses are the six that peer-to-peer
    /// transfers can produce, so filtering out the address vectors leaves the hashes covered.
    @Test
    func `Six published vectors create no address`() throws {
        let names = try PrivateTransactionHashVectors.load().vectors.filter(\.createsNoAddress).map(\.name)

        #expect(names == ["compact", "padded", "padding_moved", "two_inputs", "reordered_inputs", "single_slot_spend"])
    }

    /// Verifies the private transaction hashes of zolana's published transfers.
    ///
    /// Padding inputs enter as zero. Every output slot enters with its commitment, because the
    /// transfers pad with zero-amount outputs that the sender owns, not empty UTXOs.
    ///
    /// - Parameter transfer: A published transfer.
    @Test(arguments: TransferVectors.transfers)
    func `Hashes match the published transfers`(_ transfer: TransferVectors.Transfer) throws {
        let firstNullifier = try Poseidon.Element(hex: transfer.firstNullifier)
        let inputs = try transfer.spentInputs.map { try Poseidon.Element(hex: $0.hash) }
            + transfer.paddingInputs.map { _ in Poseidon.Element.zero }
        let outputs = try ([transfer.recipientCommitment] + transfer.senderOutputs.map(\.commitment)).map { try Poseidon.Element(hex: $0) }
        let blinding = TransactBlinding.privateTransactionBlinding(firstNullifier: firstNullifier, blindingSeed: TransferVectors.blindingSeed)

        let hash = PrivateTransactionHash.hash(inputs: inputs, outputs: outputs, blinding: blinding)

        #expect(hash.bigEndianBytes == (try fixtureBytes(transfer.privateTransactionHash)))
    }
}
