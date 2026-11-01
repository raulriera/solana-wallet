import RPC
import Testing

struct TransferProofRequestWitnessTests {
    private typealias Fixture = ProofFixtures

    @Test(arguments: [(0, 1, 3, 1), (1, 0, 3, 0), (1, 1, 2, 1), (1, 1, 3, 2)])
    func `Witnesses refuse lists without their counts`(inputs: Int, outputs: Int, publicSlots: Int, owners: Int) throws {
        let witness = try Fixture.witness()

        #expect(throws: TransferProofRequest.ValidationError.invalidCount) {
            try TransferProofRequest.Witness(
                inputs: Array(witness.inputs.prefix(inputs)), outputs: Array(witness.outputs.prefix(outputs)),
                outputTreeID: 0, blindingSeed: Fixture.field(1), externalDataHash: Fixture.field(1),
                privateTransactionHash: Fixture.field(1),
                publicAssets: Array(repeating: Fixture.field(0), count: publicSlots),
                publicAmounts: Array(repeating: Fixture.field(0), count: publicSlots), ringProgramID: Fixture.field(0),
                signerPublicKeyHashes: [], inputFlags: Fixture.field(1),
                publishedOutputOwnerPublicKeyHashes: Array(repeating: Fixture.field(0), count: owners),
                cacheTreeID: Fixture.field(0), cacheReadHashChain: Fixture.field(0)
            )
        }
    }

    @Test(arguments: [
        { _ = try TransferProofRequest.WitnessInput(utxo: ProofFixtures.utxo(), isDummy: false, treeSlot: 0,
                                                   nullifier: ProofFixtures.field(1), ownerPublicKeyHash: ProofFixtures.field(1),
                                                   nullifierSecret: Array(repeating: 1, count: 31), inclusionProof: nil,
                                                   nonInclusionProof: ProofFixtures.nonInclusionProof()) },
        { let witness = try ProofFixtures.witness()
          _ = try TransferProofRequest.Witness(
              inputs: witness.inputs, outputs: witness.outputs, outputTreeID: 0, blindingSeed: Array(repeating: 1, count: 33),
              externalDataHash: witness.externalDataHash, privateTransactionHash: witness.privateTransactionHash,
              publicAssets: witness.publicAssets, publicAmounts: witness.publicAmounts, ringProgramID: witness.ringProgramID,
              signerPublicKeyHashes: witness.signerPublicKeyHashes, inputFlags: witness.inputFlags,
              publishedOutputOwnerPublicKeyHashes: witness.publishedOutputOwnerPublicKeyHashes,
              cacheTreeID: witness.cacheTreeID, cacheReadHashChain: witness.cacheReadHashChain) },
    ] as [@Sendable () throws -> Void])
    func `Witness values must be field elements`(make: @Sendable () throws -> Void) {
        #expect(throws: TransferProofRequest.ValidationError.invalidLength) { try make() }
    }
}

struct TransferProofRequestCacheTests {
    private typealias Fixture = ProofFixtures

    @Test
    func `A zero blinding seed is refused`() {
        #expect(throws: TransferProofRequest.ValidationError.zeroBlindingSeed) {
            try Fixture.witness(blindingSeed: Fixture.field(0))
        }
    }

    @Test
    func `A valid read cache is accepted`() {
        #expect(throws: Never.self) {
            try Fixture.witness(cacheTreeID: Fixture.field(2), cacheReadHashes: [Fixture.field(4)],
                                cacheIsCached: [true], cacheReadIndexes: [0])
        }
    }

    @Test(arguments: [
        (ProofFixtures.field(0), [ProofFixtures.field(4), ProofFixtures.field(4)], [Bool](), [UInt64]()),
        (ProofFixtures.field(2), [], [], []),
        ([UInt8](repeating: 0, count: 29) + [1, 0, 0], [ProofFixtures.field(4)], [], []),
        (ProofFixtures.field(0), [ProofFixtures.field(4)], [], [1]),
        (ProofFixtures.field(0), [], [true], []),
        (ProofFixtures.field(0), [ProofFixtures.field(0)], [true], [0]),
    ] as [([UInt8], [[UInt8]], [Bool], [UInt64])])
    func `Invalid read caches are refused`(treeID: [UInt8], readHashes: [[UInt8]], isCached: [Bool], readIndexes: [UInt64]) {
        #expect(throws: TransferProofRequest.ValidationError.invalidCache) {
            try Fixture.witness(cacheTreeID: treeID, cacheReadHashes: readHashes, cacheIsCached: isCached,
                                cacheReadIndexes: readIndexes)
        }
    }
}
