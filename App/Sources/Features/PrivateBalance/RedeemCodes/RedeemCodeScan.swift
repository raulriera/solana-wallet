import Algorithms
import Privacy
import RPC
import Transactions
import Wallet

/// Reads from the indexer which of an account's one-time accounts were paid and which still hold unspent notes.
nonisolated enum RedeemCodeScan {
    /// A one-time account that a shielded transaction paid.
    struct Funding: Equatable, Sendable {
        let index: UInt32
        let address: Address
        /// The signature of the first transaction with an output for the one-time account.
        let signature: String
    }

    /// What the indexer reports for a code's one-time account.
    enum Status: Equatable, Sendable {
        /// The indexer reports no shielded transaction that paid the one-time account.
        case unfunded
        /// The one-time account holds unspent notes, with their lamports and the funding transaction's signature.
        case unspent(lamports: UInt64, signature: String)
        /// Every note that the one-time account received is spent.
        case spent
        /// The one-time account received notes whose roots their trees' accounts don't hold yet, so its code stays as
        /// it is.
        case unconfirmed
    }

    /// The number of indices that one tag read of a discovery checks.
    static let discoveryBatchSize = 500

    /// The number of indices that one tag read of a new code's index choice checks.
    static let choiceBatchSize = 20

    /// The first index outside the hardened range that one-time accounts use.
    private static let indexLimit: UInt32 = 1 << 31

    /// The most tag reads that the fundings of one batch of indices make.
    private static let maximumReadCount = 128

    /// Returns the next batch of indices to check.
    ///
    /// - Parameters:
    ///   - start: The lowest index to check.
    ///   - count: The batch's size, at most 1,000.
    /// - Returns: Up to `count` consecutive indices from `start`, below 2³¹.
    static func candidates(from start: UInt32, count: Int) -> [UInt32] {
        guard start < indexLimit else { return [] }
        return Array(start..<min(indexLimit, start + UInt32(count)))
    }

    /// Returns the index for a new code in a checked batch.
    ///
    /// - Parameters:
    ///   - candidates: The checked indices, in ascending order.
    ///   - used: The candidates that shielded transactions paid.
    /// - Returns: The first candidate above the highest used one, or `nil` when the last candidate is used.
    static func choice(in candidates: [UInt32], used: Set<UInt32>) -> UInt32? {
        guard let highest = candidates.lastIndex(where: used.contains) else { return candidates.first }
        let next = candidates.index(after: highest)
        return next < candidates.endIndex ? candidates[next] : nil
    }

    /// Reads which one-time accounts at indices shielded transactions paid.
    ///
    /// - Parameters:
    ///   - indices: The indices to check, in ascending order.
    ///   - keys: The account's keys.
    ///   - provider: The indexer of the account's network.
    /// - Returns: The used one-time accounts, in the indices' order.
    /// - Throws: A derivation, request, transport, response, or cancellation error.
    @concurrent
    static func fundings(of indices: [UInt32], from keys: PrivateBalanceKeyRecord,
                         using provider: some PrivateNoteProviding) async throws -> [Funding] {
        try await indices.chunks(ofCount: discoveryBatchSize).concurrentMap { batch in
            try await fundings(ofBatch: Array(batch), from: keys, using: provider)
        }.flatMap(\.self)
    }

    /// Reads the statuses of checked indices from the notes of their paid one-time accounts.
    ///
    /// - Parameters:
    ///   - indices: The checked indices.
    ///   - fundings: The paid one-time accounts at the checked indices.
    ///   - keys: The account's keys.
    ///   - rpc: The client of the account's network, which reads the notes' trees.
    ///   - indexer: The indexer of the account's network.
    /// - Returns: Each index's status: ``Status/unfunded`` without a funding, ``Status/unconfirmed`` while any of its
    ///   notes is unconfirmed, ``Status/unspent(lamports:signature:)`` while it holds unspent notes, and otherwise
    ///   ``Status/spent``.
    /// - Throws: A derivation, sync, or cancellation error.
    @concurrent
    static func statuses(of indices: [UInt32], funded fundings: [Funding], from keys: PrivateBalanceKeyRecord,
                         rpc: some RPC, indexer: some PrivateNoteProviding) async throws -> [UInt32: Status] {
        try await withThrowingTaskGroup(of: (UInt32, Status).self) { group in
            for funding in fundings {
                group.addTask {
                    let account = try keys.oneTimeAccount(at: funding.index).shieldedAccount
                    let state = try await NoteSyncState().syncedToEnd(for: account, rpc: rpc, indexer: indexer)
                    let status: Status = if state.hasUnconfirmedNotes {
                        .unconfirmed
                    } else if state.spendableLamports > 0 {
                        .unspent(lamports: state.spendableLamports, signature: funding.signature)
                    } else {
                        .spent
                    }
                    return (funding.index, status)
                }
            }
            var statuses = Dictionary(uniqueKeysWithValues: indices.map { ($0, Status.unfunded) })
            for try await (index, status) in group { statuses[index] = status }
            return statuses
        }
    }

    /// Reads what the indexer reports for the one-time accounts at indices.
    ///
    /// - Parameters:
    ///   - indices: The indices to check, in ascending order.
    ///   - keys: The account's keys.
    ///   - rpc: The client of the account's network, which reads the notes' trees.
    ///   - indexer: The indexer of the account's network.
    /// - Returns: Each index's status.
    /// - Throws: A derivation, sync, request, transport, response, or cancellation error.
    @concurrent
    static func statuses(of indices: [UInt32], from keys: PrivateBalanceKeyRecord, rpc: some RPC,
                         indexer: some PrivateNoteProviding) async throws -> [UInt32: Status] {
        let fundings = try await fundings(of: indices, from: keys, using: indexer)
        return try await statuses(of: indices, funded: fundings, from: keys, rpc: rpc, indexer: indexer)
    }

    /// Reads which one-time accounts at indices shielded transactions paid, with tag reads of one tag group until no
    /// more transactions come.
    ///
    /// - Parameters:
    ///   - indices: The indices to check, at most 1,000.
    ///   - keys: The account's keys.
    ///   - provider: The indexer of the account's network.
    /// - Returns: The used one-time accounts, in the indices' order.
    /// - Throws: ``RPC/RPCError/InvalidResponse/endlessStream`` if more transactions come after 128 reads, or a
    ///   derivation, request, transport, response, or cancellation error.
    private static func fundings(ofBatch indices: [UInt32], from keys: PrivateBalanceKeyRecord,
                                 using provider: some PrivateNoteProviding) async throws -> [Funding] {
        guard !indices.isEmpty else { return [] }
        let addresses = try indices.map { try keys.oneTimeAddress(at: $0) }
        let tags = addresses.map(\.bytes)
        let requested = Set(tags)
        var firsts: [[UInt8]: (slot: UInt64, signature: String)] = [:]
        var position: NoteSyncPosition?
        for _ in 0..<maximumReadCount {
            try Task.checkCancellation()
            let batch = try await provider.shieldedTransactions(taggedWith: tags, after: position)
            for transaction in batch.transactions {
                for output in transaction.outputs where requested.contains(output.viewTag) {
                    if let first = firsts[output.viewTag],
                       (first.slot, first.signature) <= (transaction.slot, transaction.signature) { continue }
                    firsts[output.viewTag] = (transaction.slot, transaction.signature)
                }
            }
            guard batch.moreComing else {
                return zip(indices, addresses).compactMap { index, address in
                    firsts[address.bytes].map { Funding(index: index, address: address, signature: $0.signature) }
                }
            }
            position = batch.position
        }
        throw RPCError.invalidResponse(.endlessStream)
    }
}
