public import Redaction

/// A request for the Groth16 proof of a default-ring confidential transfer whose prover reads the inputs' Merkle and
/// non-inclusion proofs from its indexer.
public struct IndexedTransferProofRequest: Sendable, Equatable, Redacted {
    /// An error for a value that can't form a request.
    public enum ValidationError: Error, Sendable, Equatable {
        /// A field element, commitment, or tree address isn't 32 bytes.
        case invalidLength
        /// A list doesn't have its required number of entries.
        case invalidCount
        case zeroBlindingSeed
        /// The public inputs name a read cache tree.
        case unsupportedCache
        /// Two trees share an ID or an address.
        case duplicateTree
        /// An input names a tree that the request doesn't declare, or a padding input names a tree that no earlier
        /// real input uses.
        case invalidTreeSlot
        /// A declared tree has no input.
        case unusedTree
        /// A nullifier isn't a canonical field element, or a padding input's nullifier is zero.
        case invalidNullifier
        /// A real input has no commitment, a padding input has one, or a commitment isn't a canonical field element.
        case invalidCommitment
        /// A public input isn't a canonical BN254 scalar field element.
        case nonCanonicalPublicInput
    }

    /// A tree that the prover reads the inputs' proofs from.
    public struct Tree: Sendable, Equatable {
        public let id: UInt16
        /// The tree account's 32-byte address.
        public let address: [UInt8]

        /// Creates a tree.
        ///
        /// - Parameters:
        ///   - id: The tree's ID.
        ///   - address: The tree account's 32-byte address.
        /// - Throws: ``ValidationError/invalidLength`` if the address isn't 32 bytes.
        public init(id: UInt16, address: [UInt8]) throws {
            try IndexedTransferProofRequest.validateFields([address])
            self.id = id
            self.address = address
        }
    }

    /// One input slot and the commitment that the prover reads its proofs for.
    public struct Input: Sendable, Equatable, Redacted {
        /// The spent UTXO, or padding.
        public let utxo: UTXO
        /// Whether the slot is padding.
        public let isDummy: Bool
        /// The position of the input's tree in ``IndexedTransferProofRequest/trees``.
        public let treeSlot: UInt8
        public let nullifier: [UInt8]
        /// The owner's Solana identity, or zero for padding.
        public let ownerPublicKeyHash: [UInt8]
        /// The owner's nullifier secret, right-aligned in 32 big-endian bytes, or zero for padding.
        public let nullifierSecret: [UInt8]
        /// The spent UTXO's 32-byte hash, or `nil` for padding.
        public let commitment: [UInt8]?

        /// Creates an input slot.
        ///
        /// - Parameters:
        ///   - utxo: The spent UTXO, or padding.
        ///   - isDummy: Whether the slot is padding.
        ///   - treeSlot: The position of the input's tree.
        ///   - nullifier: The published nullifier, a canonical field element that isn't zero for padding.
        ///   - ownerPublicKeyHash: The owner's Solana identity, or zero.
        ///   - nullifierSecret: The right-aligned nullifier secret, or zero.
        ///   - commitment: The spent UTXO's canonical hash, or `nil` for padding.
        /// - Throws: ``ValidationError/invalidLength`` if a value isn't 32 bytes,
        ///   ``ValidationError/invalidNullifier`` for an invalid nullifier, or ``ValidationError/invalidCommitment``
        ///   for an invalid commitment.
        public init(utxo: UTXO, isDummy: Bool, treeSlot: UInt8, nullifier: [UInt8], ownerPublicKeyHash: [UInt8],
                    nullifierSecret: [UInt8], commitment: [UInt8]?) throws {
            try IndexedTransferProofRequest.validateFields(
                [nullifier, ownerPublicKeyHash, nullifierSecret],
                commitment.map { [$0] } ?? []
            )
            guard FieldHex.isCanonical(nullifier), !isDummy || nullifier.contains(where: { $0 != 0 }) else {
                throw ValidationError.invalidNullifier
            }
            guard (commitment == nil) == isDummy, commitment.map(FieldHex.isCanonical) ?? true else {
                throw ValidationError.invalidCommitment
            }
            self.utxo = utxo
            self.isDummy = isDummy
            self.treeSlot = treeSlot
            self.nullifier = nullifier
            self.ownerPublicKeyHash = ownerPublicKeyHash
            self.nullifierSecret = nullifierSecret
            self.commitment = commitment
        }
    }

    /// The number of field elements in a transfer's statement without its tree slots.
    private static let publicInputCount = 17

    /// The position of the private transaction hash in the public inputs.
    private static let privateTransactionHashIndex = 3

    /// The position of the external data hash in the public inputs.
    private static let externalDataHashIndex = 4

    /// The position of the read cache's tree ID in the public inputs.
    private static let cacheTreeIDIndex = 15

    /// The position of the read cache's hash chain in the public inputs.
    private static let cacheReadHashChainIndex = 16

    /// The one or two trees that the inputs' tree slots index.
    public let trees: [Tree]
    public let inputs: [Input]
    public let outputs: [Output]
    /// The transfer's statement without its tree slots, as 17 field elements.
    public let publicInputs: [[UInt8]]
    /// The ID of the tree that receives the outputs.
    public let outputTreeID: UInt16
    public let blindingSeed: [UInt8]
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

    /// The hash of the instruction's external data, which the statement publishes.
    var externalDataHash: [UInt8] { publicInputs[Self.externalDataHashIndex] }

    /// The private transaction hash, which the statement publishes.
    var privateTransactionHash: [UInt8] { publicInputs[Self.privateTransactionHashIndex] }

    /// The hash chain of the read cache's empty reads, which the statement publishes.
    var cacheReadHashChain: [UInt8] { publicInputs[Self.cacheReadHashChainIndex] }

    /// Creates a request.
    ///
    /// - Parameters:
    ///   - trees: One or two trees with unique IDs and addresses.
    ///   - inputs: The input slots, at least one, each with its tree slot and commitment.
    ///   - outputs: The output slots, at least one.
    ///   - publicInputs: The statement's 17 canonical field elements, without a read cache tree.
    ///   - outputTreeID: The ID of the output tree.
    ///   - blindingSeed: The blinding seed.
    ///   - publicAssets: Three public assets.
    ///   - publicAmounts: Three public amounts.
    ///   - ringProgramID: The ring program's field element.
    ///   - signerPublicKeyHashes: The padded signer identities.
    ///   - inputFlags: The input flags.
    ///   - publishedOutputOwnerPublicKeyHashes: One owner identity per output.
    /// - Throws: A ``ValidationError`` if a count, length, tree, tree slot, or public input is invalid.
    public init(
        trees: [Tree],
        inputs: [Input],
        outputs: [Output],
        publicInputs: [[UInt8]],
        outputTreeID: UInt16,
        blindingSeed: [UInt8],
        publicAssets: [[UInt8]],
        publicAmounts: [[UInt8]],
        ringProgramID: [UInt8],
        signerPublicKeyHashes: [[UInt8]],
        inputFlags: [UInt8],
        publishedOutputOwnerPublicKeyHashes: [[UInt8]]
    ) throws {
        guard (1...2).contains(trees.count), !inputs.isEmpty, !outputs.isEmpty,
              publicInputs.count == Self.publicInputCount, publicAssets.count == 3, publicAmounts.count == 3,
              publishedOutputOwnerPublicKeyHashes.count == outputs.count else {
            throw ValidationError.invalidCount
        }
        try Self.validateFields(
            [blindingSeed, ringProgramID, inputFlags],
            publicAssets, publicAmounts, signerPublicKeyHashes, publishedOutputOwnerPublicKeyHashes, publicInputs
        )
        guard blindingSeed.contains(where: { $0 != 0 }) else { throw ValidationError.zeroBlindingSeed }
        guard Set(trees.map(\.id)).count == trees.count, Set(trees.map(\.address)).count == trees.count else {
            throw ValidationError.duplicateTree
        }
        try Self.validateTreeSlots(of: inputs, treeCount: trees.count)
        guard publicInputs.allSatisfy(FieldHex.isCanonical) else { throw ValidationError.nonCanonicalPublicInput }
        guard publicInputs[Self.cacheTreeIDIndex].allSatisfy({ $0 == 0 }) else {
            throw ValidationError.unsupportedCache
        }
        self.trees = trees
        self.inputs = inputs
        self.outputs = outputs
        self.publicInputs = publicInputs
        self.outputTreeID = outputTreeID
        self.blindingSeed = blindingSeed
        self.publicAssets = publicAssets
        self.publicAmounts = publicAmounts
        self.ringProgramID = ringProgramID
        self.signerPublicKeyHashes = signerPublicKeyHashes
        self.inputFlags = inputFlags
        self.publishedOutputOwnerPublicKeyHashes = publishedOutputOwnerPublicKeyHashes
    }

    /// Checks that every value in each list is 32 bytes.
    ///
    /// - Parameter lists: The values to check.
    /// - Throws: ``ValidationError/invalidLength`` if a value has another length.
    private static func validateFields(_ lists: [[UInt8]]...) throws {
        guard lists.allSatisfy({ $0.allSatisfy { $0.count == 32 } }) else { throw ValidationError.invalidLength }
    }

    /// Checks that each input names a declared tree, that padding names only a tree that an earlier real input uses,
    /// and that every tree has an input.
    ///
    /// - Parameters:
    ///   - inputs: The input slots.
    ///   - treeCount: The number of declared trees.
    /// - Throws: ``ValidationError/invalidTreeSlot`` for an undeclared or unopened tree, or
    ///   ``ValidationError/unusedTree`` for a tree without an input.
    private static func validateTreeSlots(of inputs: [Input], treeCount: Int) throws {
        var opened = Set<UInt8>()
        for input in inputs {
            guard Int(input.treeSlot) < treeCount, !input.isDummy || opened.contains(input.treeSlot) else {
                throw ValidationError.invalidTreeSlot
            }
            opened.insert(input.treeSlot)
        }
        guard opened.count == treeCount else { throw ValidationError.unusedTree }
    }
}

extension IndexedTransferProofRequest {
    /// A UTXO as the eight field elements that the circuit reads.
    public struct UTXO: Sendable, Equatable, Redacted {
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
            try IndexedTransferProofRequest.validateFields(
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
    }

    /// One output slot of the witness.
    public struct Output: Sendable, Equatable, Redacted {
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
            try IndexedTransferProofRequest.validateFields([hash, ownerPublicKeyHash, nullifierPublicKey])
            self.utxo = utxo
            self.isDummy = isDummy
            self.hash = hash
            self.ownerPublicKeyHash = ownerPublicKeyHash
            self.nullifierPublicKey = nullifierPublicKey
        }
    }
}
