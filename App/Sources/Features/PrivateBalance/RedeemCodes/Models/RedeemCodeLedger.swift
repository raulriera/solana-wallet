import Foundation

/// The redeem codes that one account created on one network and that may still hold SOL, the indices that code
/// preparations took before their fundings were recorded, and the index where the account's next code starts looking
/// for an unused one-time account.
///
/// A ledger that this device started by preparing or recording a code, such as after a restore or after an unreadable
/// item was deleted, isn't ``isDiscovered``: codes that the account created before then are missing until a scan of
/// the chain adds them.
nonisolated struct RedeemCodeLedger: Codable, Equatable, Sendable {
    /// The codes, by index.
    private(set) var records: [RedeemCodeRecord]
    /// The indices that code preparations took and whose fundings aren't recorded, by index.
    private(set) var pending: [PendingRedeemCode]
    /// The lowest index that no recorded, pending, or discovered code uses.
    private(set) var nextIndex: UInt32
    /// Whether a scan of the chain added the account's earlier codes.
    private(set) var isDiscovered: Bool

    /// Creates a ledger.
    /// - Parameters:
    ///   - records: The codes, in any order.
    ///   - pending: The indices that code preparations took, in any order.
    ///   - nextIndex: The lowest index that no code uses yet; at least one above every record's and pending index.
    ///   - isDiscovered: Whether a scan of the chain added the account's earlier codes.
    init(records: [RedeemCodeRecord] = [], pending: [PendingRedeemCode] = [], nextIndex: UInt32 = 0,
         isDiscovered: Bool) {
        self.records = []
        self.pending = []
        self.nextIndex = nextIndex
        self.isDiscovered = isDiscovered
        pending.forEach { hold($0) }
        records.forEach { add($0) }
    }

    /// Adds a code, replacing a record or a pending index at the same index, and moves the next index above it.
    /// - Parameter record: The code's record.
    mutating func add(_ record: RedeemCodeRecord) {
        pending.removeAll { $0.index == record.index }
        records.removeAll { $0.index == record.index }
        records.append(record)
        records.sort { $0.index < $1.index }
        raiseNextIndex(above: record.index)
    }

    /// Keeps the index that a code's preparation took until its funding is recorded, and moves the next index above
    /// it, so that no later code takes it.
    /// - Parameter code: The prepared code's index and date.
    mutating func hold(_ code: PendingRedeemCode) {
        pending.removeAll { $0.index == code.index }
        pending.append(code)
        pending.sort { $0.index < $1.index }
        raiseNextIndex(above: code.index)
    }

    /// Forgets a pending index whose funding didn't land; the next index stays, so the index is never used again.
    /// - Parameter index: The pending index.
    mutating func release(_ index: UInt32) {
        pending.removeAll { $0.index == index }
    }

    /// Removes the codes at indices, such as codes that were redeemed or taken back; the next index stays.
    /// - Parameter indices: The indices to remove.
    mutating func remove(_ indices: Set<UInt32>) {
        records.removeAll { indices.contains($0.index) }
    }

    /// Adds the codes that a scan of the chain found, keeping recorded codes at the same indices, and marks the ledger
    /// as discovered.
    /// - Parameter discovered: The ledger that the scan built.
    mutating func merge(_ discovered: RedeemCodeLedger) {
        for record in discovered.records where !records.contains(where: { $0.index == record.index }) { add(record) }
        nextIndex = max(nextIndex, discovered.nextIndex)
        isDiscovered = true
    }

    /// Applies what the indexer reports for the codes and pending indices.
    ///
    /// A code with unspent notes keeps them as its amount; a code whose funding the indexer doesn't report yet stays
    /// as it is; a code whose notes are all spent was redeemed or taken back and leaves. A pending index with unspent
    /// notes becomes a code, such as one whose app quit before recording its funding; one without them leaves once its
    /// funding can no longer land. Indices without a status stay as they are.
    /// - Parameters:
    ///   - statuses: What the indexer reports, by index.
    ///   - reserves: The public lamports of pending indices' one-time accounts, which become their codes' reserves.
    ///   - date: The current date.
    mutating func reconcile(with statuses: [UInt32: RedeemCodeScan.Status], reserves: [UInt32: UInt64],
                            at date: Date) {
        for record in records {
            switch statuses[record.index] {
            case .unspent(let lamports, _)?:
                add(RedeemCodeRecord(index: record.index, amount: lamports, reserve: record.reserve,
                                     created: record.created, fundingSignature: record.fundingSignature))
            case .spent?:
                remove([record.index])
            case .unfunded?, nil:
                break
            }
        }
        for code in pending {
            if case .unspent(let lamports, let signature)? = statuses[code.index] {
                add(RedeemCodeRecord(index: code.index, amount: lamports, reserve: reserves[code.index] ?? 0,
                                     created: code.created, fundingSignature: signature))
            } else if statuses[code.index] != nil, code.isExpired(at: date) {
                release(code.index)
            }
        }
    }

    /// Moves the next index above an index, unless that index is the highest one.
    /// - Parameter index: A used index.
    private mutating func raiseNextIndex(above index: UInt32) {
        let (above, overflow) = index.addingReportingOverflow(1)
        if !overflow { nextIndex = max(nextIndex, above) }
    }
}
