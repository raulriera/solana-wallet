/// One output of a shielded transaction, as an indexer publishes it.
///
/// The output's slot index, which note decryption binds, is its position in its transaction's ``ShieldedTransaction/outputs``.
public struct ShieldedOutput: Sendable, Equatable {
    /// The 32-byte view tag that addresses the output, such as a recipient's Ed25519 public key.
    public let viewTag: [UInt8]
    /// The 32-byte UTXO hash, which is the output's leaf in its tree.
    public let utxoHash: [UInt8]
    /// The ID of the tree that holds the leaf.
    public let treeID: UInt16
    /// The leaf's position in its tree.
    public let leafIndex: UInt64
    /// The output's published payload, such as an encrypted note, as received.
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
