/// The values of an indexer history read, which a page request sends with its pagination.
protocol IndexerQuery: Encodable, Sendable {
    /// The type of the read's pages.
    associatedtype Page: IndexerPage

    /// The indexer method name.
    static var method: String { get }
}

/// A request for one page of an indexer history read.
struct IndexerPageRequest<Query: IndexerQuery>: RPCRequest {
    typealias Response = Query.Page

    static var method: String { Query.method }
    static var maximumResponseLength: Int? { 1_048_576 }

    let query: Query
    /// Where the page starts.
    let checkpoint: IndexerCheckpoint
    /// The most transactions that the page returns.
    let limit: Int

    func encode(to encoder: any Encoder) throws {
        try query.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(checkpoint.paginationToken, forKey: .paginationToken)
        try container.encodeIfPresent(checkpoint.afterSlot.map { ["slot": ["gt": $0]] }, forKey: .filters)
        try container.encode(limit, forKey: .limit)
    }

    private enum CodingKeys: String, CodingKey {
        case paginationToken, filters, limit
    }
}

/// An indexer read of the confidential transactions with an output or message for any of the view tags.
struct GetShieldedTransactionsByTags: IndexerQuery {
    typealias Page = ShieldedTransactionPage
    static let method = "getShieldedTransactionsByTags"
    /// One to 1,000 base-58 view tags.
    let tags: [String]
}

/// An indexer read of every output whose view tag is any of the view tags.
struct GetEncryptedUtxosByTags: IndexerQuery {
    typealias Page = EncryptedOutputPage
    static let method = "getEncryptedUtxosByTags"
    /// One to 1,000 base-58 view tags.
    let tags: [String]
}

/// An indexer read of the transactions that spent any of the nullifiers.
struct GetShieldedTransactionsByNullifiers: IndexerQuery {
    typealias Page = ShieldedTransactionPage
    static let method = "getShieldedTransactionsByNullifiers"
    /// One to 1,000 base-58 nullifiers.
    let nullifiers: [String]
}

/// An indexer read of the inclusion proofs of UTXO hashes in one tree, all against one root.
struct GetMerkleProofs: RPCRequest {
    static let method = "getMerkleProofs"
    static let maximumResponseLength: Int? = 1_048_576
    typealias Response = MerkleProofList
    /// The tree account's base-58 address.
    let treeAccount: String
    /// One to 1,000 base-58 UTXO hashes.
    let leaves: [String]
}
