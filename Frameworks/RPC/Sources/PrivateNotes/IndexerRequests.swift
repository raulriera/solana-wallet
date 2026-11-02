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

/// An indexer read of the transactions that spent any of the nullifiers.
struct GetShieldedTransactionsByNullifiers: RPCRequest {
    static let method = "getShieldedTransactionsByNullifiers"
    typealias Response = ShieldedTransactionPage
    /// One to 1,000 base-58 nullifiers.
    let nullifiers: [String]
    /// The cursor to read after, or `nil` for the start.
    let cursor: String?
}
