/// A UTXO's inclusion proof in a UTXO tree.
public struct MerkleProof: Sendable, Equatable {
    /// The number of siblings in a path.
    static let height = 32

    /// The 32-byte UTXO hash that the proof places in the tree.
    public let leaf: [UInt8]
    /// The leaf's 32-byte siblings, leaf level first.
    public let path: [[UInt8]]
    public let leafIndex: UInt64
    /// The 32-byte root that the path leads to.
    public let root: [UInt8]
    /// The root's position in the tree's on-chain root history.
    public let rootIndex: UInt16
}
