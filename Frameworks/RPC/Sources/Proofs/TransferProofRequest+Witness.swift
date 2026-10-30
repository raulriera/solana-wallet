extension TransferProofRequest {
    /// A UTXO as the eight field elements that the circuit reads.
    public struct UTXO: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        /// The domain: 3 for a UTXO, or 1 for padding.
        public let domain: [UInt8]
        /// The owner hash, or zero for padding.
        public let owner: [UInt8]
        /// The asset's field element, or zero for padding.
        public let asset: [UInt8]
        /// The amount, or zero for padding.
        public let amount: [UInt8]
        public let blinding: [UInt8]
        /// The hash of the UTXO's data, or zero without data.
        public let dataHash: [UInt8]
        /// The hash of the UTXO's ring data, or zero in the default ring.
        public let ringDataHash: [UInt8]
        /// The ring program's field element, or zero in the default ring.
        public let ringProgramID: [UInt8]

        /// Creates a UTXO from its field elements.
        ///
        /// - Parameters:
        ///   - domain: The domain.
        ///   - owner: The owner hash.
        ///   - asset: The asset's field element.
        ///   - amount: The amount.
        ///   - blinding: The blinding.
        ///   - dataHash: The data hash.
        ///   - ringDataHash: The ring data hash.
        ///   - ringProgramID: The ring program's field element.
        /// - Throws: ``ValidationError/invalidLength`` if a value isn't 32 bytes.
        public init(domain: [UInt8], owner: [UInt8], asset: [UInt8], amount: [UInt8], blinding: [UInt8],
                    dataHash: [UInt8], ringDataHash: [UInt8], ringProgramID: [UInt8]) throws {
            try TransferProofRequest.validateFields(
                [domain, owner, asset, amount, blinding, dataHash, ringDataHash, ringProgramID]
            )
            self.domain = domain
            self.owner = owner
            self.asset = asset
            self.amount = amount
            self.blinding = blinding
            self.dataHash = dataHash
            self.ringDataHash = ringDataHash
            self.ringProgramID = ringProgramID
        }

        public var description: String { "TransferProofRequest.UTXO" }

        public var debugDescription: String { description }

        public var customMirror: Mirror { Mirror(self, children: [:]) }
    }

    /// One input slot of the witness.
    public struct WitnessInput: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
                                CustomReflectable {
        /// The spent UTXO, or padding.
        public let utxo: UTXO
        /// Whether the slot is padding.
        public let isDummy: Bool
        /// The position of the input's tree in ``TransferProofRequest/treeSlots``.
        public let treeSlot: UInt8
        public let nullifier: [UInt8]
        /// The owner's Solana identity, or zero for padding.
        public let ownerPublicKeyHash: [UInt8]
        /// The owner's nullifier secret, right-aligned in 32 big-endian bytes, or zero for padding.
        public let nullifierSecret: [UInt8]
        /// The spent UTXO's inclusion proof, or `nil` for padding or a cached input.
        public let inclusionProof: MerkleProof?
        /// The nullifier's non-inclusion proof under its tree slot's nullifier root.
        public let nonInclusionProof: NonInclusionProof

        /// Creates an input slot.
        ///
        /// - Parameters:
        ///   - utxo: The spent UTXO, or padding.
        ///   - isDummy: Whether the slot is padding.
        ///   - treeSlot: The position of the input's tree.
        ///   - nullifier: The published nullifier.
        ///   - ownerPublicKeyHash: The owner's Solana identity, or zero.
        ///   - nullifierSecret: The right-aligned nullifier secret, or zero.
        ///   - inclusionProof: The spent UTXO's inclusion proof, or `nil`.
        ///   - nonInclusionProof: The nullifier's non-inclusion proof.
        /// - Throws: ``ValidationError/invalidLength`` if a value isn't 32 bytes.
        public init(utxo: UTXO, isDummy: Bool, treeSlot: UInt8, nullifier: [UInt8], ownerPublicKeyHash: [UInt8],
                    nullifierSecret: [UInt8], inclusionProof: MerkleProof?, nonInclusionProof: NonInclusionProof) throws {
            try TransferProofRequest.validateFields([nullifier, ownerPublicKeyHash, nullifierSecret])
            self.utxo = utxo
            self.isDummy = isDummy
            self.treeSlot = treeSlot
            self.nullifier = nullifier
            self.ownerPublicKeyHash = ownerPublicKeyHash
            self.nullifierSecret = nullifierSecret
            self.inclusionProof = inclusionProof
            self.nonInclusionProof = nonInclusionProof
        }

        public var description: String { "TransferProofRequest.WitnessInput" }

        public var debugDescription: String { description }

        public var customMirror: Mirror { Mirror(self, children: [:]) }
    }

    /// One output slot of the witness.
    public struct WitnessOutput: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
                                 CustomReflectable {
        /// The created UTXO, or padding.
        public let utxo: UTXO
        /// Whether the slot is padding.
        public let isDummy: Bool
        /// The output's published hash.
        public let hash: [UInt8]
        /// The owner's Solana identity, or for padding the identity of its view tag's owner.
        public let ownerPublicKeyHash: [UInt8]
        /// The owner's nullifier public key, or zero for padding.
        public let nullifierPublicKey: [UInt8]

        /// Creates an output slot.
        ///
        /// - Parameters:
        ///   - utxo: The created UTXO, or padding.
        ///   - isDummy: Whether the slot is padding.
        ///   - hash: The published hash.
        ///   - ownerPublicKeyHash: The owner's Solana identity.
        ///   - nullifierPublicKey: The owner's nullifier public key, or zero.
        /// - Throws: ``ValidationError/invalidLength`` if a value isn't 32 bytes.
        public init(utxo: UTXO, isDummy: Bool, hash: [UInt8], ownerPublicKeyHash: [UInt8], nullifierPublicKey: [UInt8])
            throws {
            try TransferProofRequest.validateFields([hash, ownerPublicKeyHash, nullifierPublicKey])
            self.utxo = utxo
            self.isDummy = isDummy
            self.hash = hash
            self.ownerPublicKeyHash = ownerPublicKeyHash
            self.nullifierPublicKey = nullifierPublicKey
        }

        public var description: String { "TransferProofRequest.WitnessOutput" }

        public var debugDescription: String { description }

        public var customMirror: Mirror { Mirror(self, children: [:]) }
    }

    /// The circuit's witness, without the tree slots and the public input hash.
    public struct Witness: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let inputs: [WitnessInput]
        public let outputs: [WitnessOutput]
        /// The ID of the tree that receives the outputs.
        public let outputTreeID: UInt16
        public let blindingSeed: [UInt8]
        /// The hash of the instruction's external data.
        public let externalDataHash: [UInt8]
        public let privateTransactionHash: [UInt8]
        /// The three public slots' assets.
        public let publicAssets: [[UInt8]]
        /// The three public slots' amounts.
        public let publicAmounts: [[UInt8]]
        /// The ring program's field element, or zero in the default ring.
        public let ringProgramID: [UInt8]
        /// The signers' Solana identities, payer first, padded with zeros to the shape's signer width.
        public let signerPublicKeyHashes: [[UInt8]]
        /// The flags for whether padding inputs are allowed and each input's tree slot.
        public let inputFlags: [UInt8]
        public let publishedOutputOwnerPublicKeyHashes: [[UInt8]]
        /// The read cache's tree ID, or zero without a cache.
        public let cacheTreeID: [UInt8]
        public let cacheReadHashChain: [UInt8]
        /// The hashes that the read cache supplies, or empty without a cache.
        public let cacheReadHashes: [[UInt8]]
        /// Whether each input comes from the read cache, or empty without a cache.
        public let cacheIsCached: [Bool]
        /// Each cached input's position in the cache, or empty without a cache.
        public let cacheReadIndexes: [UInt64]

        /// Creates a witness.
        ///
        /// - Parameters:
        ///   - inputs: The input slots, at least one.
        ///   - outputs: The output slots, at least one.
        ///   - outputTreeID: The ID of the output tree.
        ///   - blindingSeed: The blinding seed.
        ///   - externalDataHash: The external data hash.
        ///   - privateTransactionHash: The private transaction hash.
        ///   - publicAssets: Three public assets.
        ///   - publicAmounts: Three public amounts.
        ///   - ringProgramID: The ring program's field element.
        ///   - signerPublicKeyHashes: The padded signer identities.
        ///   - inputFlags: The input flags.
        ///   - publishedOutputOwnerPublicKeyHashes: One owner identity per output.
        ///   - cacheTreeID: The read cache's tree ID.
        ///   - cacheReadHashChain: The read cache's hash chain.
        ///   - cacheReadHashes: The cached hashes.
        ///   - cacheIsCached: Whether each input is cached.
        ///   - cacheReadIndexes: Each cached input's position.
        /// - Throws: ``ValidationError/invalidLength`` if a value isn't 32 bytes, ``ValidationError/invalidCount`` if a
        ///   list doesn't have its count, ``ValidationError/zeroBlindingSeed`` for a zero seed, or
        ///   ``ValidationError/invalidCache`` for an invalid read cache.
        public init(
            inputs: [WitnessInput],
            outputs: [WitnessOutput],
            outputTreeID: UInt16,
            blindingSeed: [UInt8],
            externalDataHash: [UInt8],
            privateTransactionHash: [UInt8],
            publicAssets: [[UInt8]],
            publicAmounts: [[UInt8]],
            ringProgramID: [UInt8],
            signerPublicKeyHashes: [[UInt8]],
            inputFlags: [UInt8],
            publishedOutputOwnerPublicKeyHashes: [[UInt8]],
            cacheTreeID: [UInt8],
            cacheReadHashChain: [UInt8],
            cacheReadHashes: [[UInt8]] = [],
            cacheIsCached: [Bool] = [],
            cacheReadIndexes: [UInt64] = []
        ) throws {
            guard !inputs.isEmpty, !outputs.isEmpty, publicAssets.count == 3, publicAmounts.count == 3,
                  publishedOutputOwnerPublicKeyHashes.count == outputs.count else {
                throw ValidationError.invalidCount
            }
            try TransferProofRequest.validateFields(
                [blindingSeed, externalDataHash, privateTransactionHash, ringProgramID, inputFlags, cacheTreeID,
                 cacheReadHashChain],
                publicAssets, publicAmounts, signerPublicKeyHashes, publishedOutputOwnerPublicKeyHashes, cacheReadHashes
            )
            guard blindingSeed.contains(where: { $0 != 0 }) else { throw ValidationError.zeroBlindingSeed }
            try Self.validateCache(inputCount: inputs.count, treeID: cacheTreeID, readHashes: cacheReadHashes,
                                   isCached: cacheIsCached, readIndexes: cacheReadIndexes)
            self.inputs = inputs
            self.outputs = outputs
            self.outputTreeID = outputTreeID
            self.blindingSeed = blindingSeed
            self.externalDataHash = externalDataHash
            self.privateTransactionHash = privateTransactionHash
            self.publicAssets = publicAssets
            self.publicAmounts = publicAmounts
            self.ringProgramID = ringProgramID
            self.signerPublicKeyHashes = signerPublicKeyHashes
            self.inputFlags = inputFlags
            self.publishedOutputOwnerPublicKeyHashes = publishedOutputOwnerPublicKeyHashes
            self.cacheTreeID = cacheTreeID
            self.cacheReadHashChain = cacheReadHashChain
            self.cacheReadHashes = cacheReadHashes
            self.cacheIsCached = cacheIsCached
            self.cacheReadIndexes = cacheReadIndexes
        }

        /// Checks that the read cache matches the inputs.
        ///
        /// - Parameters:
        ///   - inputCount: The number of input slots.
        ///   - treeID: The cache's tree ID.
        ///   - readHashes: The cached hashes.
        ///   - isCached: Whether each input is cached.
        ///   - readIndexes: Each input's read position.
        /// - Throws: ``ValidationError/invalidCache`` if the cache is invalid.
        private static func validateCache(inputCount: Int, treeID: [UInt8], readHashes: [[UInt8]], isCached: [Bool],
                                          readIndexes: [UInt64]) throws {
            let reads = readHashes.contains { $0.contains { $0 != 0 } }
            let treeIDFits = treeID.dropLast(2).allSatisfy { $0 == 0 }
            let isTreeIDZero = treeID.allSatisfy { $0 == 0 }
            guard [readHashes.count, isCached.count, readIndexes.count].allSatisfy({ $0 == 0 || $0 == inputCount }),
                  treeIDFits, reads || isTreeIDZero,
                  readIndexes.allSatisfy({ $0 < UInt64(inputCount) }) else {
                throw ValidationError.invalidCache
            }
            for (input, cached) in isCached.enumerated() where cached {
                let index = readIndexes.isEmpty ? 0 : Int(readIndexes[input])
                guard index < readHashes.count, readHashes[index].contains(where: { $0 != 0 }) else {
                    throw ValidationError.invalidCache
                }
            }
        }

        public var description: String { "TransferProofRequest.Witness" }

        public var debugDescription: String { description }

        public var customMirror: Mirror { Mirror(self, children: [:]) }
    }
}
