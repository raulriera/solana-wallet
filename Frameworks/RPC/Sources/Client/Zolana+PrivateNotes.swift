import Encoding

extension Zolana {
    /// The most pages that one read fetches from each tag or nullifier group's stream.
    private static let indexerPageLimit = 8

    /// The most transactions that a page asks for before a page that is too long halves it.
    private static let indexerPageSize = 250

    /// The most nullifiers that one request of a spends read names.
    private static let nullifierGroupSize = 400

    /// The most leaves that one request of a proof read names, which keeps a response under the length limit.
    private static let leafGroupSize = 400

    @concurrent
    public func shieldedTransactions(taggedWith tags: [[UInt8]], after position: NoteSyncPosition?) async throws
        -> ShieldedTransactionBatch {
        guard tags.allSatisfy({ $0.count == 32 }) else { throw PrivateNoteError.invalidTag }
        let groups = tags.map(Base58.encode).batches(of: 1_000)
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
            .uniqued(by: { TransactionKey(signature: $0.signature, eventIndex: $0.eventIndex) })
        let deposits = outputs.flatMap(\.items).compactMap(\.deposit).uniqued(by: DepositKey.init)
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
        let groups = nullifiers.map(Base58.encode).batches(of: Self.nullifierGroupSize)
        let indexer = indexer
        let checkpoints = [IndexerCheckpoint](repeating: .start, count: groups.count)
        let reads = try await Self.read(groups, after: checkpoints) { nullifiers, checkpoint, limit in
            try await Self.page(GetShieldedTransactionsByNullifiers(nullifiers: nullifiers), at: checkpoint,
                                limit: limit, from: indexer)
        }
        return Self.ordered(reads.flatMap(\.items).map(\.value)
            .uniqued(by: { TransactionKey(signature: $0.signature, eventIndex: $0.eventIndex) }))
    }

    @concurrent
    public func merkleProofs(for leaves: [[UInt8]], inTree tree: String) async throws -> [MerkleProof] {
        guard leaves.allSatisfy({ $0.count == 32 }) else { throw PrivateNoteError.invalidLeaf }
        guard Base58.decode(tree, byteCount: 32) != nil else { throw PrivateNoteError.invalidTree }
        let indexer = indexer
        return try await Self.map(leaves.batches(of: Self.leafGroupSize)) { batch in
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
        try await Self.map(Array(zip(groups, checkpoints))) { values, checkpoint in
            try await Page.read(from: checkpoint, pageLimit: Self.indexerPageLimit, pageSize: Self.indexerPageSize) {
                try await page(values, $0, $1)
            }
        }
    }

    /// Transforms each group concurrently.
    ///
    /// - Parameters:
    ///   - groups: The groups to transform.
    ///   - transform: The work for one group.
    /// - Returns: Each group's result, in group order.
    /// - Throws: The first error of any group.
    private static func map<Group: Sendable, Result: Sendable>(
        _ groups: [Group],
        _ transform: @escaping @Sendable (Group) async throws -> Result
    ) async throws -> [Result] {
        try await withThrowingTaskGroup(of: (Int, Result).self) { group in
            for (index, value) in groups.enumerated() {
                group.addTask { (index, try await transform(value)) }
            }
            var results = [Result?](repeating: nil, count: groups.count)
            for try await (index, result) in group { results[index] = result }
            return results.compactMap(\.self)
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

/// The identity of a proofless deposit's output.
private struct DepositKey: Hashable {
    let signature: String
    let treeID: UInt16
    let leafIndex: UInt64
    let utxoHash: [UInt8]
}

extension DepositKey {
    /// Creates the identity of a deposit's output.
    ///
    /// - Parameter deposit: A proofless deposit with one output.
    init(_ deposit: ShieldedTransaction) {
        signature = deposit.signature
        treeID = deposit.outputs.first?.treeID ?? 0
        leafIndex = deposit.outputs.first?.leafIndex ?? 0
        utxoHash = deposit.outputs.first?.utxoHash ?? []
    }
}
