import Testing
import RPC

/// Verifies the checks and redaction of transfer proof requests.
struct TransferProofRequestTests {
    private typealias Fixture = ProofFixtures

    /// Verifies requests without one or two tree slots, or whose input names an undeclared slot, are refused.
    ///
    /// - Parameters:
    ///   - slots: The tree slots' IDs.
    ///   - error: The expected refusal.
    /// - Throws: A failed test prerequisite.
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

    /// Verifies an input that names a tree slot the request doesn't declare is refused.
    ///
    /// - Throws: A failed test prerequisite.
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

    /// Verifies the public input hash and tree roots must be 32 bytes.
    ///
    /// - Parameter make: Creates a part with a value of another length.
    @Test(arguments: [
        { _ = try TransferProofRequest(treeSlots: [ProofFixtures.treeSlot()], publicInputHash: [1], witness: ProofFixtures.witness()) },
        { _ = try TransferProofRequest.TreeSlot(id: 0, utxoRoot: [1], nullifierRoot: ProofFixtures.field(1)) },
        { _ = try TransferProofRequest.TreeSlot(id: 0, utxoRoot: ProofFixtures.field(1), nullifierRoot: Array(repeating: 1, count: 33)) },
    ] as [@Sendable () throws -> Void])
    func `Hashes and roots must be 32 bytes`(make: @Sendable () throws -> Void) {
        #expect(throws: TransferProofRequest.ValidationError.invalidLength) { try make() }
    }

    /// Verifies descriptions, debug descriptions, and dumps reveal none of the witness's values.
    ///
    /// The fixture's secrets end in bytes `a1`, `b1`, `c1`, and `d1`, whose decimal and hexadecimal forms
    /// would appear in a reflected array.
    /// - Throws: A validation error, which the fixture doesn't produce.
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

/// Verifies that inclusion proofs agree with their witness inputs: only a real input that isn't cached has one.
struct TransferProofRequestInclusionTests {
    private typealias Fixture = ProofFixtures

    /// Creates a request whose one input has the given witness.
    /// - Parameters:
    ///   - isDummy: Whether the input pads its slot.
    ///   - cached: Whether the input comes from the read cache.
    ///   - hasInclusionProof: Whether the input carries an inclusion proof.
    /// - Returns: The request.
    /// - Throws: A ``TransferProofRequest/ValidationError`` if the parts disagree.
    private static func request(isDummy: Bool, cached: Bool, hasInclusionProof: Bool) throws -> TransferProofRequest {
        let witness = try Fixture.witness(
            isDummy: isDummy, hasInclusionProof: hasInclusionProof, cacheTreeID: cached ? Fixture.field(2) : Fixture.field(0),
            cacheReadHashes: cached ? [Fixture.field(4)] : [], cacheIsCached: cached ? [true] : [], cacheReadIndexes: cached ? [0] : []
        )
        return try TransferProofRequest(treeSlots: [Fixture.treeSlot()], publicInputHash: Fixture.field(1), witness: witness)
    }

    /// Verifies inputs that agree with their inclusion proofs are accepted: a real input with one, and a cached
    /// input and padding without one.
    ///
    /// - Parameters:
    ///   - isDummy: Whether the input pads its slot.
    ///   - cached: Whether the input is cached.
    ///   - hasInclusionProof: Whether the input carries an inclusion proof.
    @Test(arguments: [(false, false, true), (false, true, false), (true, false, false)])
    func `Inputs that agree with their inclusion proofs are accepted`(isDummy: Bool, cached: Bool, hasInclusionProof: Bool) {
        #expect(throws: Never.self) {
            try Self.request(isDummy: isDummy, cached: cached, hasInclusionProof: hasInclusionProof)
        }
    }

    /// Verifies inputs that disagree with their inclusion proofs are refused.
    ///
    /// - Parameters:
    ///   - isDummy: Whether the input pads its slot.
    ///   - cached: Whether the input is cached.
    ///   - hasInclusionProof: Whether the input carries an inclusion proof.
    @Test(arguments: [(false, false, false), (false, true, true), (true, false, true)])
    func `Inputs that disagree with their inclusion proofs are refused`(isDummy: Bool, cached: Bool, hasInclusionProof: Bool) {
        #expect(throws: TransferProofRequest.ValidationError.invalidInclusionProof) {
            try Self.request(isDummy: isDummy, cached: cached, hasInclusionProof: hasInclusionProof)
        }
    }
}
