import ModularArithmetic
import RPC
import Transactions

/// The UTXO roots that a tree's account holds on chain, the roots that a note's inclusion proof must lead to.
struct UTXORootHistory: Sendable {
    /// The tree account's data, which holds the roots.
    private let data: [UInt8]

    /// The number of slots that hold a root.
    let count: Int

    /// Returns whether a Merkle proof places a leaf in the history's tree under a root that the history holds.
    ///
    /// - Parameters:
    ///   - leaf: The note's UTXO hash.
    ///   - leafIndex: The note's position in its tree.
    ///   - tree: The note's tree account, whose roots the history holds.
    ///   - proof: An inclusion proof of the leaf from the tree.
    /// - Returns: ``ReceivedNote/InclusionStatus/refuted`` if the proof's leaf, leaf index, or tree isn't the note's,
    ///   or its path doesn't lead the leaf to its root; ``ReceivedNote/InclusionStatus/included`` if the history holds
    ///   that root at the proof's root index; otherwise ``ReceivedNote/InclusionStatus/unconfirmed``.
    func inclusionStatus(of leaf: Poseidon.Element, at leafIndex: UInt64, in tree: Address, provenBy proof: MerkleProof)
        -> ReceivedNote.InclusionStatus {
        guard proof.tree == tree.bytes, proof.leaf == leaf.bigEndianBytes, proof.leafIndex == leafIndex,
              Self.root(of: leaf, at: leafIndex, along: proof.path)?.bigEndianBytes == proof.root else {
            return .refuted
        }
        return root(at: Int(proof.rootIndex))?.elementsEqual(proof.root) == true ? .included : .unconfirmed
    }

    /// Returns the root in one of the history's slots.
    ///
    /// - Parameter slot: The slot's position.
    /// - Returns: The slot's 32 bytes, or `nil` if the slot doesn't hold a root.
    func root(at slot: Int) -> ArraySlice<UInt8>? {
        guard (0..<count).contains(slot) else { return nil }
        let start = ShieldedPool.TreeAccount.utxoRootsOffset + slot * 32
        return data[start..<start + 32]
    }

    /// Hashes a leaf up its path to the root.
    ///
    /// - Parameters:
    ///   - leaf: The leaf.
    ///   - index: The leaf's position, whose bit at each level is 1 where the path's node is a right child.
    ///   - path: The 32-byte siblings, leaf level first.
    /// - Returns: The root, or `nil` if the index doesn't fit the path's height or a sibling isn't a canonical field
    ///   element.
    private static func root(of leaf: Poseidon.Element, at index: UInt64, along path: [[UInt8]]) -> Poseidon.Element? {
        guard index >> path.count == 0 else { return nil }
        var node = leaf
        for (level, bytes) in path.enumerated() {
            guard let sibling = Poseidon.Element(bigEndianBytes: bytes) else { return nil }
            node = (index >> level) & 1 == 0 ? Poseidon.hash(node, sibling) : Poseidon.hash(sibling, node)
        }
        return node
    }
}

extension UTXORootHistory {
    /// Reads the history from a tree account's data.
    ///
    /// - Parameter data: The tree account's data, as ``ShieldedPool/treeAccountData(at:using:)`` returns it.
    /// - Throws: ``ShieldedPool/TreeError/invalidRootHistory`` if the history's capacity isn't 500 or its cursor and
    ///   count don't describe written roots.
    init(accountData data: [UInt8]) throws {
        typealias Layout = ShieldedPool.TreeAccount
        let cursor = Int(data.littleEndian(at: Layout.utxoRootCursorOffset) as UInt16)
        let count = Int(data.littleEndian(at: Layout.utxoRootCountOffset) as UInt16)
        let capacity = Int(data.littleEndian(at: Layout.utxoRootCapacityOffset) as UInt16)
        guard capacity == Layout.utxoRootCapacity, (1...Layout.utxoRootCapacity).contains(count),
              cursor < Layout.utxoRootCapacity, count == Layout.utxoRootCapacity || cursor + 1 == count else {
            throw ShieldedPool.TreeError.invalidRootHistory
        }
        self.data = data
        self.count = count
    }
}
