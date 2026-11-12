import Algorithms
import Encoding

extension Zolana {
    /// The most pages that one read fetches from each tag or nullifier group's stream.
    private static let indexerPageLimit = 8

    /// The most transactions that a page asks for before a page that is too long halves it.
    private static let indexerPageSize = 250

    /// The most nullifiers that one request of a spends read names.
    private static let nullifierGroupSize = 400

    /// The most leaves that one request of a proof read names, which is the indexer's limit.
    private static let leafGroupSize = 64

    @concurrent
    public func shieldedTransactions(taggedWith tags: [[UInt8]], after position: NoteSyncPosition?) async throws
        -> ShieldedTransactionBatch {
        guard tags.allSatisfy({ $0.count == 32 }) else { throw PrivateNoteError.invalidTag }
        let groups = tags.map(Base58.encode).chunks(ofCount: 1_000).map(Array.init)
        let start = position ?? NoteSyncPosition(tags: tags, groupCount: groups.count)
        guard start.matches(tags, groupCount: groups.count) else { throw PrivateNoteError.mismatchedPosition }
        let indexer = indexer
        async let transactionReads = Self.read(groups, after: start.transactionCheckpoints) { tags, checkpoint, limit in
            try await Self.page(GetShieldedTransactionsByTags(tags: tags), at: checkpoint, limit: limit, from: indexer)
        }
        async let outputReads = Self.read(groups, after: start.outputCheckpoints) { tags, checkpoint, limit in
            try await Self.page(GetEncryptedUtxosByTags(tags: tags), at: checkpoint, limit: limit, from: indexer)
        }
        let (transactions, outputs) = try await (transactionReads, outputReads)

        let confidential = transactions.flatMap(\.items).filter { !$0.isInRing }.map(\.value)
            .filter { !$0.isProofless }
            .uniqued(on: { TransactionKey(signature: $0.signature, eventIndex: $0.eventIndex) })
        let deposits = outputs.flatMap(\.items).uniqued(on: DepositKey.init).compactMap(\.deposit)
        return ShieldedTransactionBatch(
            transactions: Self.ordered(confidential + deposits),
            outputTreeID: transactions.lazy.compactMap(\.outputTreeID).first
                ?? outputs.lazy.compactMap(\.outputTreeID).first,
            position: NoteSyncPosition(tags: tags, transactionCheckpoints: transactions.map(\.resume),
                                       outputCheckpoints: outputs.map(\.resume)),
            moreComing: !transactions.allSatisfy(\.isComplete) || !outputs.allSatisfy(\.isComplete)
        )
    }

    @concurrent
    public func shieldedTransactions(spending nullifiers: [[UInt8]]) async throws -> [ShieldedTransaction] {
        guard nullifiers.allSatisfy({ $0.count == 32 }) else { throw PrivateNoteError.invalidNullifier }
        let groups = nullifiers.map(Base58.encode).chunks(ofCount: Self.nullifierGroupSize).map(Array.init)
        let indexer = indexer
        let checkpoints = [IndexerCheckpoint](repeating: .start, count: groups.count)
        let reads = try await Self.read(groups, after: checkpoints) { nullifiers, checkpoint, limit in
            try await Self.page(GetShieldedTransactionsByNullifiers(nullifiers: nullifiers), at: checkpoint,
                                limit: limit, from: indexer)
        }
        return Self.ordered(reads.flatMap(\.items).map(\.value)
            .uniqued(on: { TransactionKey(signature: $0.signature, eventIndex: $0.eventIndex) }))
    }

    @concurrent
    public func merkleProofs(for leaves: [[UInt8]], inTree tree: String) async throws -> [MerkleProof] {
        guard leaves.allSatisfy({ $0.count == 32 }) else { throw PrivateNoteError.invalidLeaf }
        guard Base58.decode(tree, byteCount: 32) != nil else { throw PrivateNoteError.invalidTree }
        let indexer = indexer
        return try await leaves.chunks(ofCount: Self.leafGroupSize).concurrentMap { batch in
            try await indexer.send(GetMerkleProofs(treeAccount: tree, leaves: batch.map(Base58.encode)),
                                   at: GetMerkleProofs.method).proofs.map(\.proof)
        }.flatMap(\.self)
    }

    /// Requests one page of an indexer history read at its method's route.
    ///
    /// - Parameters:
    ///   - query: The read's method and values.
    ///   - checkpoint: Where the page starts.
    ///   - limit: The most transactions that the page returns.
    ///   - indexer: The indexer's client.
    /// - Returns: The decoded page.
    /// - Throws: ``RPCError/InvalidResponse/oversized`` for a response body longer than 1 MiB, another ``RPCError``,
    ///   or `CancellationError`.
    private static func page<Query: IndexerQuery>(_ query: Query, at checkpoint: IndexerCheckpoint, limit: Int,
                                                  from indexer: HTTPClient) async throws -> Query.Page {
        try await indexer.send(IndexerPageRequest(query: query, checkpoint: checkpoint, limit: limit), at: Query.method)
    }

    /// Reads one stream for each group of values concurrently, each from its checkpoint to its end or the page limit.
    ///
    /// - Parameters:
    ///   - groups: The values of each request.
    ///   - checkpoints: The starting checkpoint of each group.
    ///   - page: The request that fetches a group's page at a checkpoint with a page size.
    /// - Returns: The read of each group, in group order.
    /// - Throws: The first error of any group.
    private static func read<Page: IndexerPage>(
        _ groups: [[String]],
        after checkpoints: [IndexerCheckpoint],
        page: @escaping @Sendable ([String], IndexerCheckpoint, Int) async throws -> Page
    ) async throws -> [IndexerRead<Page.Item>] {
        try await zip(groups, checkpoints).concurrentMap { values, checkpoint in
            try await Page.read(from: checkpoint, pageLimit: Self.indexerPageLimit, pageSize: Self.indexerPageSize) {
                try await page(values, $0, $1)
            }
        }
    }

    /// Orders transactions by slot, then signature.
    ///
    /// - Parameter transactions: The transactions to order.
    /// - Returns: The ordered transactions.
    private static func ordered(_ transactions: [ShieldedTransaction]) -> [ShieldedTransaction] {
        transactions.sorted { ($0.slot, $0.signature) < ($1.slot, $1.signature) }
    }
}

/// The identity of an indexed transaction event.
private struct TransactionKey: Hashable {
    let signature: String
    /// The event's position in the transaction, or `nil` if unknown.
    let eventIndex: UInt16?
}

/// The identity of an output that matched a view tag.
private struct DepositKey: Hashable {
    let signature: String
    let treeID: UInt16
    let leafIndex: UInt64
    let utxoHash: [UInt8]
}

extension DepositKey {
    /// Creates the identity of a matched output.
    ///
    /// - Parameter match: An output that matched a view tag.
    init(_ match: EncryptedOutput) {
        signature = match.signature
        treeID = match.output.treeID
        leafIndex = match.output.leafIndex
        utxoHash = match.output.utxoHash
    }
}
