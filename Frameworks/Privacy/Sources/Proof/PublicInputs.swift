import ModularArithmetic

/// The statement that a default-ring transact proof commits to, and its public input hash.
struct PublicInputs: Sendable, Equatable {
    /// One of a proof's tree slots, with a declared input tree and the roots that its inputs are proven against.
    struct TreeSlot: Sendable, Equatable {
        let treeID: UInt16
        let utxoRoot: Poseidon.Element
        let nullifierRoot: Poseidon.Element

        var hash: Poseidon.Element {
            Poseidon.hash(Poseidon.Element(UInt64(treeID)), utxoRoot, nullifierRoot)
        }
    }

    static let treeSlotCount = 5

    static let publicSlotCount = 3

    /// The nullifier of each input slot, padding included.
    let nullifiers: [Poseidon.Element]

    /// The UTXO hash of each output slot, padding included.
    let outputHashes: [Poseidon.Element]

    let outputTreeID: UInt16

    let privateTransactionHash: Poseidon.Element

    let externalDataHash: Poseidon.Element

    /// The asset commitment of each public slot, or zero for an unused slot.
    let publicAssets: [Poseidon.Element]

    /// The amount of each public slot, `r - amount` for a withdrawal, or zero for an unused slot.
    let publicAmounts: [Poseidon.Element]

    /// The ring program, zero in the default ring.
    let ringProgramID: Poseidon.Element

    /// The identities of the fee payer, then each other input owner, then zeros up to the shape's signer width.
    let signerIdentities: [Poseidon.Element]

    let inputFlags: Poseidon.Element

    let outputOwnerIdentities: [Poseidon.Element]

    /// The tree of the cache that inputs are read from, zero without a cache.
    let cacheTreeID: Poseidon.Element

    /// The chain of the cache reads, ``HashChain/zeroSuffix(groups:)`` without a cache.
    let cacheReadHashChain: Poseidon.Element

    /// The 17 elements of the statement without the tree slots, in order.
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
    /// - Parameter treeSlots: The declared trees' slots, in declaration order.
    /// - Returns: The public input hash.
    func hash(treeSlots: [TreeSlot]) -> Poseidon.Element {
        Self.hash(elements: elements, treeSlots: treeSlots)
    }

    /// Hashes a statement's elements with the roots of its input trees.
    ///
    /// - Parameters:
    ///   - elements: The statement's elements without the tree slots.
    ///   - treeSlots: The declared trees' slots, in declaration order.
    /// - Returns: The left chain of `elements` with the tree slots' chain inserted at index 2.
    static func hash(elements: [Poseidon.Element], treeSlots: [TreeSlot]) -> Poseidon.Element {
        precondition(elements.count >= 2, "The tree slots' chain follows the nullifier and output chains.")
        var preimage = elements
        preimage.insert(treeSlotsChain(treeSlots), at: 2)
        return HashChain.left4(preimage)
    }

    /// Folds the tree slots, padded with unused slots to 5.
    ///
    /// - Parameter treeSlots: The declared trees' slots, in declaration order.
    /// - Returns: The right chain of the 5 slots' hashes.
    static func treeSlotsChain(_ treeSlots: [TreeSlot]) -> Poseidon.Element {
        precondition(treeSlots.count <= treeSlotCount, "A proof has 5 tree slots.")
        let unused = TreeSlot(treeID: 0, utxoRoot: .zero, nullifierRoot: .zero)
        let slots = treeSlots + Array(repeating: unused, count: treeSlotCount - treeSlots.count)
        return HashChain.right(slots.map(\.hash))
    }
}
