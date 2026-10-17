import ModularArithmetic

/// The statement that a default-ring transact proof commits to, and its public input hash.
///
/// A transfer proof has one public input, the hash of 18 field elements, as zolana's
/// `PublicInputs::hash` builds it:
///
/// 1. the right chain (``HashChain/right4(_:)``) of the nullifiers,
/// 2. the right chain of the output UTXO hashes,
/// 3. the right chain (``HashChain/right(_:)``) of the 5 tree slots' hashes,
/// 4. the output tree's ID, the private transaction hash, and the external data hash,
/// 5. the 3 public asset and amount slots, interleaved,
/// 6. the ring program, the right chain of the signer identities, and the input flags,
/// 7. the right chain of the output owner identities, and the cache's tree and read chain.
///
/// The hash is the left chain (``HashChain/left4(_:)``) of these elements. The tree slots' roots come
/// from the indexer's proofs, so the statement holds the other 17 elements, ``elements``, and the hash
/// inserts the tree slots' chain at index 2.
struct PublicInputs: Sendable, Equatable {
    /// One of a proof's tree slots: a declared input tree and the roots that its inputs are proven
    /// against.
    ///
    /// The slots of the declared trees come first, in declaration order. Unused slots have zero for
    /// every value, and their hash, `Poseidon(0, 0, 0)`, isn't zero.
    struct TreeSlot: Sendable, Equatable {
        /// The tree's ID.
        let treeID: UInt16
        /// The UTXO tree's root.
        let utxoRoot: Poseidon.Element
        /// The nullifier tree's root.
        let nullifierRoot: Poseidon.Element

        /// The slot's hash, `Poseidon(tree ID, UTXO root, nullifier root)`.
        var hash: Poseidon.Element {
            Poseidon.hash(Poseidon.Element(UInt64(treeID)), utxoRoot, nullifierRoot)
        }
    }

    /// The number of tree slots that every transact proof publishes, `INPUT_TREES`.
    static let treeSlotCount = 5

    /// The number of public asset slots that every transact proof publishes, `N_PUBLIC_SLOTS`.
    static let publicSlotCount = 3

    /// The nullifier of each input slot, padding included.
    let nullifiers: [Poseidon.Element]

    /// The UTXO hash of each output slot, padding included.
    let outputHashes: [Poseidon.Element]

    /// The ID of the tree that receives the outputs.
    let outputTreeID: UInt16

    /// The private transaction hash.
    let privateTransactionHash: Poseidon.Element

    /// The external data hash.
    let externalDataHash: Poseidon.Element

    /// The asset of each public slot: an asset's commitment, or zero for an unused slot.
    let publicAssets: [Poseidon.Element]

    /// The amount of each public slot: positive for a deposit, `r - amount` for a withdrawal, or
    /// zero for an unused slot.
    let publicAmounts: [Poseidon.Element]

    /// The ring program, zero in the default ring.
    let ringProgramID: Poseidon.Element

    /// The identities of the transaction's signers: the fee payer, then each other input owner,
    /// then zeros up to the shape's signer width.
    let signerIdentities: [Poseidon.Element]

    /// The packed input flags.
    let inputFlags: Poseidon.Element

    /// The identity of each output slot's owner tag.
    let outputOwnerIdentities: [Poseidon.Element]

    /// The tree of the cache that inputs are read from, zero without a cache.
    let cacheTreeID: Poseidon.Element

    /// The chain of the cache reads, ``HashChain/zeroSuffix(groups:)`` without a cache.
    let cacheReadHashChain: Poseidon.Element

    /// The 17 elements of the statement without the tree slots, in order.
    ///
    /// - Precondition: There are 3 public assets and amounts, and one owner identity per output.
    var elements: [Poseidon.Element] {
        precondition(publicAssets.count == Self.publicSlotCount && publicAmounts.count == Self.publicSlotCount, "A proof has 3 public slots.")
        precondition(outputOwnerIdentities.count == outputHashes.count, "Each output slot has an owner identity.")
        let publicSlots = zip(publicAssets, publicAmounts).flatMap { [$0, $1] }
        return [
            HashChain.right4(nullifiers),
            HashChain.right4(outputHashes),
            Poseidon.Element(UInt64(outputTreeID)),
            privateTransactionHash,
            externalDataHash,
        ] + publicSlots + [
            ringProgramID,
            HashChain.right(signerIdentities),
            inputFlags,
            HashChain.right4(outputOwnerIdentities),
            cacheTreeID,
            cacheReadHashChain,
        ]
    }

    /// Hashes the statement with the roots of its input trees.
    ///
    /// - Parameter treeSlots: The declared trees' slots, in declaration order; at most 5.
    /// - Returns: The public input hash.
    func hash(treeSlots: [TreeSlot]) -> Poseidon.Element {
        Self.hash(elements: elements, treeSlots: treeSlots)
    }

    /// Hashes a statement's elements with the roots of its input trees.
    ///
    /// - Parameters:
    ///   - elements: The elements without the tree slots, such as ``elements``.
    ///   - treeSlots: The declared trees' slots, in declaration order; at most 5.
    /// - Returns: The left chain of `elements` with the tree slots' chain inserted at index 2.
    /// - Precondition: `elements` holds at least two elements, and there are at most 5 slots.
    static func hash(elements: [Poseidon.Element], treeSlots: [TreeSlot]) -> Poseidon.Element {
        precondition(elements.count >= 2, "The tree slots' chain follows the nullifier and output chains.")
        var preimage = elements
        preimage.insert(treeSlotsChain(treeSlots), at: 2)
        return HashChain.left4(preimage)
    }

    /// Folds the tree slots, padded with unused slots to 5, `tree_slots_hash_chain`.
    ///
    /// - Parameter treeSlots: The declared trees' slots, in declaration order; at most 5.
    /// - Returns: The right chain of the 5 slots' hashes.
    /// - Precondition: There are at most 5 slots.
    static func treeSlotsChain(_ treeSlots: [TreeSlot]) -> Poseidon.Element {
        precondition(treeSlots.count <= treeSlotCount, "A proof has 5 tree slots.")
        let unused = TreeSlot(treeID: 0, utxoRoot: .zero, nullifierRoot: .zero)
        let slots = treeSlots + Array(repeating: unused, count: treeSlotCount - treeSlots.count)
        return HashChain.right(slots.map(\.hash))
    }
}
