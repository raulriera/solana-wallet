import Testing
import RPC

struct TransferProofRequestTests {
    private typealias Fixture = ProofFixtures

    @Test(arguments: [
        ([UInt16](), TransferProofRequest.ValidationError.invalidCount),
        ([0, 1, 2], .invalidCount),
    ])
    func `Requests need one or two tree slots`(slots: [UInt16], error: TransferProofRequest.ValidationError) throws {
        let treeSlots = try slots.map { try TransferProofRequest.TreeSlot(id: $0, utxoRoot: Fixture.field(1), nullifierRoot: Fixture.field(2)) }

        #expect(throws: error) {
            try TransferProofRequest(treeSlots: treeSlots, publicInputHash: Fixture.field(1), witness: Fixture.witness())
        }
    }

    @Test
    func `Inputs must name a declared tree slot`() throws {
        let witness = try Fixture.witness()
        let input = try #require(witness.inputs.first)
        let moved = try TransferProofRequest.WitnessInput(
            utxo: input.utxo, isDummy: input.isDummy, treeSlot: 1, nullifier: input.nullifier,
            ownerPublicKeyHash: input.ownerPublicKeyHash, nullifierSecret: input.nullifierSecret,
            inclusionProof: input.inclusionProof, nonInclusionProof: input.nonInclusionProof
        )
        let edited = try TransferProofRequest.Witness(
            inputs: [moved], outputs: witness.outputs, outputTreeID: witness.outputTreeID, blindingSeed: witness.blindingSeed,
            externalDataHash: witness.externalDataHash, privateTransactionHash: witness.privateTransactionHash,
            publicAssets: witness.publicAssets, publicAmounts: witness.publicAmounts, ringProgramID: witness.ringProgramID,
            signerPublicKeyHashes: witness.signerPublicKeyHashes, inputFlags: witness.inputFlags,
            publishedOutputOwnerPublicKeyHashes: witness.publishedOutputOwnerPublicKeyHashes,
            cacheTreeID: witness.cacheTreeID, cacheReadHashChain: witness.cacheReadHashChain
        )

        #expect(throws: TransferProofRequest.ValidationError.invalidTreeSlot) {
            try TransferProofRequest(treeSlots: [Fixture.treeSlot()], publicInputHash: Fixture.field(1), witness: edited)
        }
    }

    @Test(arguments: [
        { _ = try TransferProofRequest(treeSlots: [ProofFixtures.treeSlot()], publicInputHash: [1], witness: ProofFixtures.witness()) },
        { _ = try TransferProofRequest.TreeSlot(id: 0, utxoRoot: [1], nullifierRoot: ProofFixtures.field(1)) },
        { _ = try TransferProofRequest.TreeSlot(id: 0, utxoRoot: ProofFixtures.field(1), nullifierRoot: Array(repeating: 1, count: 33)) },
    ] as [@Sendable () throws -> Void])
    func `Hashes and roots must be 32 bytes`(make: @Sendable () throws -> Void) {
        #expect(throws: TransferProofRequest.ValidationError.invalidLength) { try make() }
    }

    @Test
    func `Descriptions reveal no witness values`() throws {
        let request = try Fixture.request()
        var dump = ""
        Swift.dump(request, to: &dump)
        Swift.dump(request.witness, to: &dump)
        Swift.dump(request.witness.inputs, to: &dump)
        Swift.dump(request.witness.outputs, to: &dump)

        let text = [String(describing: request), String(reflecting: request), String(describing: request.witness),
                    String(reflecting: request.witness.inputs[0].utxo), dump].joined(separator: "\n")

        #expect(["161", "177", "193", "209", "a1", "b1", "c1", "d1"].allSatisfy { !text.contains($0) })
    }
}

struct TransferProofRequestInclusionTests {
    private typealias Fixture = ProofFixtures

    private static func request(isDummy: Bool, cached: Bool, hasInclusionProof: Bool) throws -> TransferProofRequest {
        let witness = try Fixture.witness(
            isDummy: isDummy, hasInclusionProof: hasInclusionProof, cacheTreeID: cached ? Fixture.field(2) : Fixture.field(0),
            cacheReadHashes: cached ? [Fixture.field(4)] : [], cacheIsCached: cached ? [true] : [], cacheReadIndexes: cached ? [0] : []
        )
        return try TransferProofRequest(treeSlots: [Fixture.treeSlot()], publicInputHash: Fixture.field(1), witness: witness)
    }

    @Test(arguments: [(false, false, true), (false, true, false), (true, false, false)])
    func `Inputs that agree with their inclusion proofs are accepted`(isDummy: Bool, cached: Bool, hasInclusionProof: Bool) {
        #expect(throws: Never.self) {
            try Self.request(isDummy: isDummy, cached: cached, hasInclusionProof: hasInclusionProof)
        }
    }

    @Test(arguments: [(false, false, false), (false, true, true), (true, false, true)])
    func `Inputs that disagree with their inclusion proofs are refused`(isDummy: Bool, cached: Bool, hasInclusionProof: Bool) {
        #expect(throws: TransferProofRequest.ValidationError.invalidInclusionProof) {
            try Self.request(isDummy: isDummy, cached: cached, hasInclusionProof: hasInclusionProof)
        }
    }
}
