import ModularArithmetic
import Testing
@testable import Privacy

struct PrivateTransactionHashTests {
    @Test(arguments: try NonzeroHashChainVectors.load().vectors)
    func `Chains match the published vectors`(_ vector: NonzeroHashChainVectors.Chain) throws {
        let elements = try vector.inputs.map { try Poseidon.Element(hex: $0) }

        #expect(PrivateTransactionHash.nonzeroChain(elements).bigEndianBytes == (try fixtureBytes(vector.output)))
    }

    @Test(arguments: try PrivateTransactionHashVectors.load().vectors.filter(\.createsNoAddress))
    func `Hashes match the published vectors`(_ vector: PrivateTransactionHashVectors.Hash) throws {
        let hash = PrivateTransactionHash.hash(
            inputs: try vector.inputHashes.map { try Poseidon.Element(hex: $0) },
            outputs: try vector.outputHashes.map { try Poseidon.Element(hex: $0) },
            blinding: try Poseidon.Element(hex: vector.blinding)
        )

        #expect(hash.bigEndianBytes == (try fixtureBytes(vector.privateTransactionHash)))
    }

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
