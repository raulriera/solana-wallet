import ModularArithmetic
import RPC

extension NoteSyncState {
    /// The most transactions that a sync reads to confirm claimed spends of counted notes.
    private static let maximumSpendReads = 8

    /// The number of reads in a row that find no transaction for a claimed spend before the claim counts as refuted.
    private static let maximumMissingReads = 10

    /// Confirms the indexer's claims that transactions spent counted notes by reading the oldest claimed transactions
    /// that the sync hasn't read and that this state doesn't count as refuted.
    ///
    /// - Parameters:
    ///   - transactions: The indexer's transactions, with the nullifiers that each claims to spend.
    ///   - reads: The claimed spends that the sync already read, which this adds to.
    ///   - rpc: The client that reads the transactions at finalized commitment.
    /// - Returns: The nullifiers that the read transactions spent, the signatures of the refuted claims that a claim
    ///   still names, and the reads in a row that found no transaction for each claim that a claim still names.
    /// - Throws: ``ShieldedPool/InstructionError/unknownLayout`` if a successful transaction holds a spend instruction
    ///   of an unknown layout, or a request, transport, response, or cancellation error.
    func confirmedSpends(
        in transactions: [ShieldedTransaction],
        reads: inout SpendReads,
        using rpc: some RPC
    ) async throws -> (proven: Set<[UInt8]>, rejected: Set<String>, missingReads: [String: Int]) {
        let counted = SpendClaim.claims(in: transactions, of: Set(notes.map(\.nullifier.bigEndianBytes)))
        let claimed = Set(counted.map(\.signature))
        let named = rejectedSpends.intersection(claimed)
        let unread = counted.unread(by: reads, skipping: named, limit: Self.maximumSpendReads)
        let (proven, refuted, missing) = try await Self.confirm(unread, recording: &reads, using: rpc)
        let (missingReads, expired) = missingReads(adding: missing, read: Set(unread.map(\.signature)), claimed: claimed)
        return (proven, named.union(refuted).union(expired), missingReads)
    }

    /// Counts the reads in a row that found no transaction for each claimed spend that a claim still names.
    ///
    /// - Parameters:
    ///   - missing: The signatures of the read claims whose transactions the client didn't find.
    ///   - read: The signatures of the claims that the batch read.
    ///   - claimed: The signatures of the claims of counted notes.
    /// - Returns: The counts below the limit by signature, and the signatures whose count reached it.
    private func missingReads(adding missing: Set<String>, read: Set<String>, claimed: Set<String>)
        -> (counts: [String: Int], expired: Set<String>) {
        var counts = missingSpendReads.filter { claimed.contains($0.key) && !read.contains($0.key) }
        for signature in missing { counts[signature] = missingSpendReads[signature, default: 0] + 1 }
        let expired = Set(counts.filter { $0.value >= Self.maximumMissingReads }.keys)
        return (counts.filter { !expired.contains($0.key) }, expired)
    }

    /// Reads the transactions of claimed spends at once.
    ///
    /// - Parameters:
    ///   - claims: The claims to read.
    ///   - reads: The claimed spends that the sync read, which this adds to.
    ///   - rpc: The client that reads the transactions at finalized commitment.
    /// - Returns: The nullifiers that the transactions spent, the signatures of the finalized transactions that
    ///   failed or don't spend every nullifier that their claim names, and the signatures whose transactions the
    ///   client didn't find.
    /// - Throws: ``ShieldedPool/InstructionError/unknownLayout`` if a successful transaction holds a spend instruction
    ///   of an unknown layout, or a request, transport, response, or cancellation error.
    private static func confirm(
        _ claims: [SpendClaim],
        recording reads: inout SpendReads,
        using rpc: some RPC
    ) async throws -> (proven: Set<[UInt8]>, refuted: Set<String>, missing: Set<String>) {
        reads.record(claims)
        return try await withThrowingTaskGroup(of: (claim: SpendClaim, spent: Set<[UInt8]>?).self) { group in
            for claim in claims {
                group.addTask {
                    guard let transaction = try await rpc.send(GetTransaction(signature: claim.signature)) else { return (claim, nil) }
                    return (claim, transaction.error == nil ? try ShieldedPool.nullifiers(spentBy: transaction) : [])
                }
            }
            var proven = Set<[UInt8]>()
            var refuted = Set<String>()
            var missing = Set<String>()
            for try await (claim, spent) in group {
                guard let spent else {
                    missing.insert(claim.signature)
                    continue
                }
                proven.formUnion(spent)
                if !claim.nullifiers.isSubset(of: spent) { refuted.insert(claim.signature) }
            }
            return (proven, refuted, missing)
        }
    }
}
