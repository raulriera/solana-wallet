/// One output of a shielded transaction.
public struct ShieldedOutput: Sendable, Equatable {
    /// The 32-byte view tag that addresses the output.
    public let viewTag: [UInt8]
    /// The 32-byte UTXO hash, the output's leaf in its tree.
    public let utxoHash: [UInt8]
    /// The ID of the tree that holds the leaf.
    public let treeID: UInt16
    public let leafIndex: UInt64
    /// The published payload, such as an encrypted note.
    public let payload: [UInt8]

    /// Creates an output from its published fields.
    ///
    /// - Parameters:
    ///   - viewTag: The 32-byte view tag.
    ///   - utxoHash: The 32-byte UTXO hash.
    ///   - treeID: The ID of the tree that holds the leaf.
    ///   - leafIndex: The leaf's position in its tree.
    ///   - payload: The published payload.
    public init(viewTag: [UInt8], utxoHash: [UInt8], treeID: UInt16, leafIndex: UInt64, payload: [UInt8]) {
        self.viewTag = viewTag
        self.utxoHash = utxoHash
        self.treeID = treeID
        self.leafIndex = leafIndex
        self.payload = payload
    }
}
