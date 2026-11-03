import RPC

/// An indexer's claim that a transaction spent counted notes.
struct SpendClaim: Sendable, Equatable {
    let signature: String
    let slot: UInt64
    /// The counted notes' nullifiers that the claim names.
    let nullifiers: Set<[UInt8]>

    /// Collects the claims that name counted notes, one per transaction.
    ///
    /// - Parameters:
    ///   - transactions: The indexer's transactions, with the nullifiers that each claims to spend.
    ///   - counted: The nullifiers of the counted notes.
    /// - Returns: One claim per signature that names a counted note, with every counted nullifier that the
    ///   transactions with that signature name, oldest first.
    static func claims(in transactions: [ShieldedTransaction], of counted: Set<[UInt8]>) -> [SpendClaim] {
        let named = Dictionary(grouping: transactions.filter { !counted.isDisjoint(with: $0.nullifiers) }, by: \.signature)
        return named.map { signature, transactions in
            SpendClaim(
                signature: signature, slot: transactions.map(\.slot).min() ?? 0,
                nullifiers: counted.intersection(transactions.flatMap(\.nullifiers))
            )
        }.sorted { ($0.slot, $0.signature) < ($1.slot, $1.signature) }
    }
}

extension [SpendClaim] {
    /// Chooses the claims to read: for each nullifier that the sync hasn't read a claim of, its oldest claim that isn't
    /// skipped, oldest first, until the sync has read a number of claims.
    ///
    /// - Parameters:
    ///   - reads: The claimed spends that the sync already read.
    ///   - skipped: The signatures of claims not to read.
    ///   - limit: The most claims that one sync reads.
    /// - Returns: The claims to read, oldest first.
    func unread(by reads: SpendReads, skipping skipped: Set<String>, limit: Int) -> [SpendClaim] {
        var covered = reads.nullifiers
        var chosen: [SpendClaim] = []
        for claim in self where reads.signatures.count + chosen.count < limit {
            guard !skipped.contains(claim.signature), !reads.signatures.contains(claim.signature),
                  !claim.nullifiers.isSubset(of: covered) else { continue }
            chosen.append(claim)
            covered.formUnion(claim.nullifiers)
        }
        return chosen
    }
}

/// The claimed spends that one sync read, across the batches of a sync to the end.
struct SpendReads {
    /// The signatures of the transactions that the sync read.
    private(set) var signatures: Set<String> = []
    /// The nullifiers whose claims the sync read.
    private(set) var nullifiers: Set<[UInt8]> = []

    /// Adds claims that the sync reads.
    ///
    /// - Parameter claims: The claims.
    mutating func record(_ claims: [SpendClaim]) {
        signatures.formUnion(claims.map(\.signature))
        nullifiers.formUnion(claims.flatMap(\.nullifiers))
    }
}
