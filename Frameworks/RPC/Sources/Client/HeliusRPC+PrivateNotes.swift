import Encoding

extension HeliusRPC: PrivateNoteProviding {
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

    /// Reads one stream for each group of values concurrently, each from its cursor to its end.
    ///
    /// - Parameters:
    ///   - groups: The values of each request.
    ///   - cursors: The starting cursor of each group.
    ///   - page: The request that fetches a group's page after a cursor.
    /// - Returns: The read of each group, in group order.
    /// - Throws: The first error of any group.
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

    /// Orders transactions by slot, then signature.
    ///
    /// - Parameter transactions: The transactions to order.
    /// - Returns: The ordered transactions.
    private static func ordered(_ transactions: [ShieldedTransaction]) -> [ShieldedTransaction] {
        transactions.sorted { ($0.slot, $0.signature) < ($1.slot, $1.signature) }
    }
}

/// The reads of one indexer stream for every tag group.
private enum StreamReads: Sendable {
    case transactions([IndexerRead<IndexedTransaction>])
    case outputs([IndexerRead<EncryptedOutput>])
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
