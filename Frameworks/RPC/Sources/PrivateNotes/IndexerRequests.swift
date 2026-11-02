/// An indexer read of the confidential transactions with an output or message for any of the view tags.
struct GetShieldedTransactionsByTags: RPCRequest {
    static let method = "getShieldedTransactionsByTags"
    typealias Response = ShieldedTransactionPage
    /// One to 1,000 base-58 view tags.
    let tags: [String]
    /// The cursor to read after, or `nil` for the start.
    let cursor: String?
}

/// An indexer read of every output whose view tag is any of the view tags.
struct GetEncryptedUtxosByTags: RPCRequest {
    static let method = "getEncryptedUtxosByTags"
    typealias Response = EncryptedOutputPage
    /// One to 1,000 base-58 view tags.
    let tags: [String]
    /// The cursor to read after, or `nil` for the start.
    let cursor: String?
}

/// An indexer read of the inclusion proofs of UTXO hashes in one tree, all against one root.
struct GetMerkleProofs: RPCRequest {
    static let method = "getMerkleProofs"
    typealias Response = MerkleProofList
    /// The tree account's base-58 address.
    let treeAccount: String
    /// One to 1,000 base-58 UTXO hashes.
    let leaves: [String]
}

/// An indexer read of the transactions that spent any of the nullifiers.
struct GetShieldedTransactionsByNullifiers: RPCRequest {
    static let method = "getShieldedTransactionsByNullifiers"
    typealias Response = ShieldedTransactionPage
    /// One to 1,000 base-58 nullifiers.
    let nullifiers: [String]
    /// The cursor to read after, or `nil` for the start.
    let cursor: String?
}
