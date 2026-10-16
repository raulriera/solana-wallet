/// An indexer read of the confidential transactions with an output or message for any of the view tags.
///
/// The request omits `limit`, so the indexer's default page size of 1,000 applies, and `ringProgramId`.
/// Without that filter the indexer returns transactions of every ring; each row names its ring, if any.
struct GetShieldedTransactionsByTags: RPCRequest {
    /// The indexer method, which is also the route below the gateway.
    static let method = "getShieldedTransactionsByTags"
    /// A page of transactions.
    typealias Response = ShieldedTransactionPage
    /// One to 1,000 base-58 view tags.
    let tags: [String]
    /// The cursor to read after, or `nil` for the start.
    let cursor: String?
}

/// An indexer read of every output whose view tag is any of the view tags, one row per output.
///
/// The request omits `limit` and `ringProgramId` like ``GetShieldedTransactionsByTags``.
struct GetEncryptedUtxosByTags: RPCRequest {
    /// The indexer method, which is also the route below the gateway.
    static let method = "getEncryptedUtxosByTags"
    /// A page of matching outputs.
    typealias Response = EncryptedOutputPage
    /// One to 1,000 base-58 view tags.
    let tags: [String]
    /// The cursor to read after, or `nil` for the start.
    let cursor: String?
}

/// An indexer read of the transactions that spent any of the nullifiers.
///
/// The request omits `limit`, so the indexer's default page size of 1,000 applies.
struct GetShieldedTransactionsByNullifiers: RPCRequest {
    /// The indexer method, which is also the route below the gateway.
    static let method = "getShieldedTransactionsByNullifiers"
    /// A page of transactions.
    typealias Response = ShieldedTransactionPage
    /// One to 1,000 base-58 nullifiers.
    let nullifiers: [String]
    /// The cursor to read after, or `nil` for the start.
    let cursor: String?
}
