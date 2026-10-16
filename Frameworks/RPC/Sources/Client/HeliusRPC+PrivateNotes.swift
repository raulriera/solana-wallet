import Encoding

extension HeliusRPC: PrivateNoteProviding {
    /// Reads Helius's Solana Rings indexer by view tag, through both of its streams to their ends.
    ///
    /// Requests carry at most 1,000 tags. Each group of tags reads its confidential-transaction stream,
    /// without proofless rows or rows that name a ring, and its encrypted-output stream, keeping only outputs
    /// without a transaction viewing key and salt, which are proofless deposits. Groups and streams run
    /// concurrently, and the first failure cancels the rest. A transaction that several groups return appears once.
    ///
    /// Encrypted-output rows don't name their ring, so a deposit into another ring isn't filtered here; its
    /// UTXO hash, which binds the ring, doesn't match a default-ring note.
    /// - Parameters:
    ///   - tags: 32-byte view tags.
    ///   - position: The position from an earlier read of the same tags, or `nil` to read from the start.
    /// - Returns: The transactions in slot and signature order, the newest unpaused tree, preferring the
    ///   transaction stream's report, and the position where the next read resumes.
    /// - Throws: ``PrivateNoteError`` for an invalid tag or a position from other tags, or an `RPCError`
    ///   or `CancellationError`.
    @concurrent
    public func shieldedTransactions(taggedWith tags: [[UInt8]], after position: NoteSyncPosition?) async throws
        -> ShieldedTransactionBatch {
        guard tags.allSatisfy({ $0.count == 32 }) else { throw PrivateNoteError.invalidTag }
        let groups = tags.map(Base58.encode).batches(of: 1_000)
        let start = position ?? NoteSyncPosition(tags: tags, groupCount: groups.count)
        guard start.matches(tags, groupCount: groups.count) else { throw PrivateNoteError.mismatchedPosition }
        let gateway = gateway
        let (transactions, outputs) = try await withThrowingTaskGroup(of: StreamReads.self) { group in
            group.addTask {
                .transactions(try await Self.read(groups, after: start.transactionCursors) { tags, cursor in
                    try await gateway.send(GetShieldedTransactionsByTags(tags: tags, cursor: cursor),
                                           at: GetShieldedTransactionsByTags.method)
                })
            }
            group.addTask {
                .outputs(try await Self.read(groups, after: start.outputCursors) { tags, cursor in
                    try await gateway.send(GetEncryptedUtxosByTags(tags: tags, cursor: cursor),
                                           at: GetEncryptedUtxosByTags.method)
                })
            }
            var transactions: [IndexerRead<IndexedTransaction>] = []
            var outputs: [IndexerRead<EncryptedOutput>] = []
            for try await reads in group {
                switch reads {
                case .transactions(let reads): transactions = reads
                case .outputs(let reads): outputs = reads
                }
            }
            return (transactions, outputs)
        }

        let confidential = transactions.flatMap(\.items).filter { !$0.isInRing }.map(\.value)
            .filter { !$0.isProofless }
            .uniqued(by: { TransactionKey(signature: $0.signature, eventIndex: $0.eventIndex) })
        let deposits = outputs.flatMap(\.items).compactMap(\.deposit).uniqued(by: DepositKey.init)
        return ShieldedTransactionBatch(
            transactions: Self.ordered(confidential + deposits),
            outputTreeID: transactions.lazy.compactMap(\.outputTreeID).first
                ?? outputs.lazy.compactMap(\.outputTreeID).first,
            position: NoteSyncPosition(tags: tags, transactionCursors: transactions.map(\.resumeCursor),
                                       outputCursors: outputs.map(\.resumeCursor))
        )
    }

    /// Reads Helius's Solana Rings indexer for the transactions that spent any of the nullifiers.
    ///
    /// Requests carry at most 1,000 nullifiers and run concurrently, each to its last page. Spends in any
    /// ring are kept, since each one consumes its nullifier.
    /// - Parameter nullifiers: 32-byte nullifiers.
    /// - Returns: Each spending transaction once, in slot and signature order.
    /// - Throws: ``PrivateNoteError/invalidNullifier`` for a nullifier that isn't 32 bytes, or an `RPCError`
    ///   or `CancellationError`.
    @concurrent
    public func shieldedTransactions(spending nullifiers: [[UInt8]]) async throws -> [ShieldedTransaction] {
        guard nullifiers.allSatisfy({ $0.count == 32 }) else { throw PrivateNoteError.invalidNullifier }
        let groups = nullifiers.map(Base58.encode).batches(of: 1_000)
        let gateway = gateway
        let reads = try await Self.read(groups, after: Array(repeating: nil, count: groups.count)) { nullifiers, cursor in
            try await gateway.send(GetShieldedTransactionsByNullifiers(nullifiers: nullifiers, cursor: cursor),
                                   at: GetShieldedTransactionsByNullifiers.method)
        }
        return Self.ordered(reads.flatMap(\.items).map(\.value)
            .uniqued(by: { TransactionKey(signature: $0.signature, eventIndex: $0.eventIndex) }))
    }

    /// Reads one stream for each group of values concurrently, each from its own cursor to its end.
    ///
    /// - Parameters:
    ///   - groups: The values of each request, such as tags.
    ///   - cursors: Each group's starting cursor, in group order.
    ///   - page: Fetches one group's page after a cursor.
    /// - Returns: Each group's read, in group order.
    /// - Throws: The first error of any group, which cancels the others.
    private static func read<Page: IndexerPage>(
        _ groups: [[String]],
        after cursors: [String?],
        page: @escaping @Sendable ([String], String?) async throws -> Page
    ) async throws -> [IndexerRead<Page.Item>] {
        try await withThrowingTaskGroup(of: (Int, IndexerRead<Page.Item>).self) { group in
            for (index, values) in groups.enumerated() {
                group.addTask {
                    (index, try await Page.readAll(from: cursors[index]) { try await page(values, $0) })
                }
            }
            var reads = [IndexerRead<Page.Item>?](repeating: nil, count: groups.count)
            for try await (index, read) in group { reads[index] = read }
            return reads.compactMap(\.self)
        }
    }

    /// Orders transactions by slot, then signature, keeping the input order of equal keys.
    ///
    /// - Parameter transactions: The transactions to order.
    /// - Returns: The ordered transactions.
    private static func ordered(_ transactions: [ShieldedTransaction]) -> [ShieldedTransaction] {
        transactions.sorted { ($0.slot, $0.signature) < ($1.slot, $1.signature) }
    }
}

/// The reads of one of a tag read's two streams, for every tag group.
private enum StreamReads: Sendable {
    /// The confidential-transaction stream's reads.
    case transactions([IndexerRead<IndexedTransaction>])
    /// The encrypted-output stream's reads.
    case outputs([IndexerRead<EncryptedOutput>])
}

/// The identity of an indexed transaction event.
private struct TransactionKey: Hashable {
    /// The transaction's signature.
    let signature: String
    /// The event's position within the transaction, if reported.
    let eventIndex: UInt16?
}

/// The identity of a proofless deposit's output.
private struct DepositKey: Hashable {
    /// The transaction's signature.
    let signature: String
    /// The ID of the output's tree.
    let treeID: UInt16
    /// The output's leaf position.
    let leafIndex: UInt64
    /// The output's UTXO hash.
    let utxoHash: [UInt8]
}

extension DepositKey {
    /// Creates the identity of a deposit's only output.
    ///
    /// - Parameter deposit: A proofless deposit with one output.
    init(_ deposit: ShieldedTransaction) {
        signature = deposit.signature
        treeID = deposit.outputs.first?.treeID ?? 0
        leafIndex = deposit.outputs.first?.leafIndex ?? 0
        utxoHash = deposit.outputs.first?.utxoHash ?? []
    }
}
