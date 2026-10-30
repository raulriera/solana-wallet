/// A UTXO's inclusion proof in a UTXO tree.
public struct MerkleProof: Sendable, Equatable {
    /// The number of siblings in a path.
    public static let height = 32

    public let leaf: [UInt8]
    /// The leaf's siblings, leaf level first.
    public let path: [[UInt8]]
    public let leafIndex: UInt64
    public let root: [UInt8]
    /// The root's position in the tree's on-chain root history.
    public let rootIndex: UInt16

    /// Creates a proof.
    ///
    /// - Parameters:
    ///   - leaf: The 32-byte UTXO hash.
    ///   - path: The 32 siblings of 32 bytes, leaf level first.
    ///   - leafIndex: The leaf's position.
    ///   - root: The 32-byte root.
    ///   - rootIndex: The root's position in its history.
    /// - Throws: ``PrivateNoteError/invalidProof`` if a value isn't 32 bytes or the path doesn't have 32 siblings.
    public init(leaf: [UInt8], path: [[UInt8]], leafIndex: UInt64, root: [UInt8], rootIndex: UInt16) throws {
        guard path.count == Self.height, ([leaf, root] + path).allSatisfy({ $0.count == 32 }) else {
            throw PrivateNoteError.invalidProof
        }
        self.leaf = leaf
        self.path = path
        self.leafIndex = leafIndex
        self.root = root
        self.rootIndex = rootIndex
    }
}
