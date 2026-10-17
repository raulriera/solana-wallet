import Testing
import RPC

/// Verifies the checks of a transfer witness and its slots.
struct TransferProofRequestWitnessTests {
    private typealias Fixture = ProofFixtures

    /// Verifies witnesses whose lists don't have their counts are refused.
    ///
    /// - Parameters:
    ///   - inputs: The number of input slots.
    ///   - outputs: The number of output slots.
    ///   - publicSlots: The number of public assets and amounts.
    ///   - owners: The number of published output owners.
    /// - Throws: A failed test prerequisite.
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

    /// Verifies every slot and witness value must be a 32-byte field element.
    ///
    /// - Parameter make: Creates a part with one value of another length.
    @Test(arguments: [
        { _ = try TransferProofRequest.UTXO(domain: [3], owner: ProofFixtures.field(0), asset: ProofFixtures.field(0),
                                           amount: ProofFixtures.field(0), blinding: ProofFixtures.field(0),
                                           dataHash: ProofFixtures.field(0), ringDataHash: ProofFixtures.field(0),
                                           ringProgramID: ProofFixtures.field(0)) },
        { _ = try TransferProofRequest.WitnessInput(utxo: ProofFixtures.utxo(), isDummy: false, treeSlot: 0,
                                                   nullifier: ProofFixtures.field(1), ownerPublicKeyHash: ProofFixtures.field(1),
                                                   nullifierSecret: Array(repeating: 1, count: 31), inclusionProof: nil,
                                                   nonInclusionProof: ProofFixtures.nonInclusionProof()) },
        { _ = try TransferProofRequest.WitnessOutput(utxo: ProofFixtures.utxo(), isDummy: false, hash: [],
                                                    ownerPublicKeyHash: ProofFixtures.field(1),
                                                    nullifierPublicKey: ProofFixtures.field(1)) },
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

/// Verifies the witness's blinding seed and read cache follow zolana's prover rules.
struct TransferProofRequestCacheTests {
    private typealias Fixture = ProofFixtures

    /// Verifies a zero blinding seed is refused.
    @Test
    func `A zero blinding seed is refused`() {
        #expect(throws: TransferProofRequest.ValidationError.zeroBlindingSeed) {
            try Fixture.witness(blindingSeed: Fixture.field(0))
        }
    }

    /// Verifies a read cache that zolana's `CacheSelectionParams.Validate` accepts is accepted.
    @Test
    func `A valid read cache is accepted`() {
        #expect(throws: Never.self) {
            try Fixture.witness(cacheTreeID: Fixture.field(2), cacheReadHashes: [Fixture.field(4)],
                                cacheIsCached: [true], cacheReadIndexes: [0])
        }
    }

    /// Verifies read caches that break zolana's rules are refused.
    ///
    /// - Parameters:
    ///   - treeID: The cache's tree ID.
    ///   - readHashes: The cached hashes.
    ///   - isCached: Whether the input is cached.
    ///   - readIndexes: The input's read position.
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
