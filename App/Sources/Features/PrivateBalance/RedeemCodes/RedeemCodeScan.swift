import Privacy
import RPC
import Transactions
import Wallet

/// Reads from the indexer which of an account's one-time accounts shielded transactions paid and which still hold
/// unspent notes, so that a new code never reuses an index, a listing knows each code's state, and a restored device
/// finds the account's earlier codes.
///
/// A one-time account is used once any output carries its address as the view tag, whether or not its code was
/// redeemed since; the indexer's history keeps it used. A code's state comes from the indexer alone, never from the
/// one-time account's public lamports, which a lagging node can under-report and anyone can top up.
nonisolated enum RedeemCodeScan {
    /// A one-time account that a shielded transaction paid.
    struct Funding: Equatable, Sendable {
        /// The one-time account's index under the code root.
        let index: UInt32
        /// The one-time account's address.
        let address: Address
        /// The signature of the first transaction with an output for the one-time account.
        let signature: String
    }

    /// What the indexer reports for a code's one-time account.
    enum Status: Equatable, Sendable {
        /// No shielded transaction paid the one-time account, or the indexer doesn't report it yet.
        case unfunded
        /// The one-time account holds unspent notes of these lamports; the funding transaction has this signature.
        case unspent(lamports: UInt64, signature: String)
        /// A shielded transaction paid the one-time account, and every note that it received is spent.
        case spent
    }

    /// The number of indices that one tag read of a discovery checks, half of the indexer's 1,000 tags per request,
    /// so that the gaps that abandoned preparations leave are much shorter than a batch.
    static let discoveryBatchSize = 500

    /// The number of indices that one tag read of a new code's index choice checks. The choice starts at the codes
    /// entry's next index, above every pending index, so the batch only finds codes that another device created.
    static let choiceBatchSize = 20

    /// The first index outside the hardened range that one-time accounts use.
    private static let indexLimit: UInt32 = 1 << 31

    /// Lists the next batch of indices to check.
    /// - Parameters:
    ///   - start: The lowest index to check.
    ///   - count: The batch's size, at most 1,000, such as ``discoveryBatchSize`` or ``choiceBatchSize``.
    /// - Returns: Up to `count` consecutive indices from `start` up, below 2³¹; empty when none remain.
    static func candidates(from start: UInt32, count: Int) -> [UInt32] {
        guard start < indexLimit else { return [] }
        return Array(start..<min(indexLimit, start + UInt32(count)))
    }

    /// Picks the index for a new code in a checked batch: the first candidate above the highest used one.
    /// - Parameters:
    ///   - candidates: The checked indices, in ascending order.
    ///   - used: The candidates that shielded transactions paid.
    /// - Returns: The first candidate above the highest used one, or the first candidate when none is used; `nil`
    ///   when the last candidate is used, so that the next batch is checked.
    static func choice(in candidates: [UInt32], used: Set<UInt32>) -> UInt32? {
        guard let highest = candidates.lastIndex(where: used.contains) else { return candidates.first }
        let next = candidates.index(after: highest)
        return next < candidates.endIndex ? candidates[next] : nil
    }

    /// Reads which one-time accounts at indices shielded transactions paid, with one tag read from the start of the
    /// indexer's history per ``discoveryBatchSize`` indices, run concurrently.
    ///
    /// Only the one-time accounts' addresses are derived, not their private-balance keys.
    /// - Parameters:
    ///   - indices: The indices to check, in ascending order.
    ///   - keys: The account's kept keys, whose code root derives the one-time accounts.
    ///   - provider: The indexer of the account's network.
    /// - Returns: The used one-time accounts, in the indices' order.
    /// - Throws: A derivation error, or a request, transport, response, or cancellation error.
    @concurrent
    static func fundings(of indices: [UInt32], from keys: PrivateBalanceKeyRecord,
                         using provider: some PrivateNoteProviding) async throws -> [Funding] {
        let batches = stride(from: 0, to: indices.count, by: discoveryBatchSize).map {
            Array(indices[$0..<min($0 + discoveryBatchSize, indices.count)])
        }
        return try await withThrowingTaskGroup(of: (Int, [Funding]).self) { group in
            for (position, batch) in batches.enumerated() {
                group.addTask { (position, try await fundings(ofBatch: batch, from: keys, using: provider)) }
            }
            var found = [[Funding]](repeating: [], count: batches.count)
            for try await (position, fundings) in group { found[position] = fundings }
            return found.flatMap(\.self)
        }
    }

    /// Reads the unspent notes of one-time accounts that shielded transactions paid, each with its own sync from the
    /// start, run concurrently; the first error cancels the others.
    /// - Parameters:
    ///   - fundings: The paid one-time accounts.
    ///   - keys: The account's kept keys, whose code root derives the one-time accounts' keys.
    ///   - provider: The indexer of the account's network.
    /// - Returns: The lamports of each one-time account's unspent notes, by index, for those that hold any.
    /// - Throws: A derivation, sync, or cancellation error.
    @concurrent
    static func unspentLamports(of fundings: [Funding], from keys: PrivateBalanceKeyRecord,
                                using provider: some PrivateNoteProviding) async throws -> [UInt32: UInt64] {
        try await withThrowingTaskGroup(of: (UInt32, UInt64).self) { group in
            for funding in fundings {
                group.addTask {
                    let account = try keys.oneTimeAccount(at: funding.index).shieldedAccount
                    let state = try await NoteSyncState().synced(for: account, using: provider)
                    return (funding.index, state.lamports)
                }
            }
            var unspent: [UInt32: UInt64] = [:]
            for try await (index, lamports) in group where lamports > 0 { unspent[index] = lamports }
            return unspent
        }
    }

    /// Reads what the indexer reports for the one-time accounts at indices.
    ///
    /// The tag reads finish before the syncs start, so a sync never misses a funding that a tag read saw: a one-time
    /// account counts as spent only when the indexer that reported its funding reports no unspent note for it.
    /// - Parameters:
    ///   - indices: The indices to check, in ascending order.
    ///   - keys: The account's kept keys, whose code root derives the one-time accounts.
    ///   - provider: The indexer of the account's network.
    /// - Returns: Each index's status.
    /// - Throws: A derivation, sync, or cancellation error, or a request, transport, or response error.
    @concurrent
    static func statuses(of indices: [UInt32], from keys: PrivateBalanceKeyRecord,
                         using provider: some PrivateNoteProviding) async throws -> [UInt32: Status] {
        let fundings = try await fundings(of: indices, from: keys, using: provider)
        let unspent = try await unspentLamports(of: fundings, from: keys, using: provider)
        var statuses = Dictionary(uniqueKeysWithValues: indices.map { ($0, Status.unfunded) })
        for funding in fundings {
            statuses[funding.index] = unspent[funding.index].map { .unspent(lamports: $0, signature: funding.signature) }
                ?? .spent
        }
        return statuses
    }

    /// Reads which one-time accounts at indices shielded transactions paid, with one tag read.
    /// - Parameters:
    ///   - indices: At most 1,000 indices.
    ///   - keys: The account's kept keys, whose code root derives the one-time accounts.
    ///   - provider: The indexer of the account's network.
    /// - Returns: The used one-time accounts, in the indices' order.
    /// - Throws: A derivation error, or a request, transport, response, or cancellation error.
    private static func fundings(ofBatch indices: [UInt32], from keys: PrivateBalanceKeyRecord,
                                 using provider: some PrivateNoteProviding) async throws -> [Funding] {
        guard !indices.isEmpty else { return [] }
        let addresses = try indices.map { try keys.oneTimeAddress(at: $0) }
        let batch = try await provider.shieldedTransactions(taggedWith: addresses.map(\.bytes), after: nil)
        var firstSignatures: [[UInt8]: String] = [:]
        for transaction in batch.transactions {
            for output in transaction.outputs where firstSignatures[output.viewTag] == nil {
                firstSignatures[output.viewTag] = transaction.signature
            }
        }
        return zip(indices, addresses).compactMap { index, address in
            firstSignatures[address.bytes].map { Funding(index: index, address: address, signature: $0) }
        }
    }
}
