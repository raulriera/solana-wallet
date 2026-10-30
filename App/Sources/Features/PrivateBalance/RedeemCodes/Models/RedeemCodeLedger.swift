import Foundation

/// The redeem codes that an account created on a network, with its pending indices and next index.
nonisolated struct RedeemCodeLedger: Codable, Equatable, Sendable {
    /// The codes, sorted by index.
    private(set) var records: [RedeemCodeRecord]
    /// The indices that code preparations took and whose fundings aren't recorded, sorted by index.
    private(set) var pending: [PendingRedeemCode]
    /// The lowest index that no recorded, pending, or discovered code uses.
    private(set) var nextIndex: UInt32
    /// Whether a scan of the chain added the account's earlier codes.
    private(set) var isDiscovered: Bool

    /// Creates a ledger.
    ///
    /// - Parameters:
    ///   - records: The codes, in any order.
    ///   - pending: The indices that code preparations took, in any order.
    ///   - nextIndex: The lowest index that no code uses.
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
    ///
    /// - Parameter record: The code's record.
    mutating func add(_ record: RedeemCodeRecord) {
        pending.removeAll { $0.index == record.index }
        records.removeAll { $0.index == record.index }
        records.append(record)
        records.sort { $0.index < $1.index }
        raiseNextIndex(above: record.index)
    }

    /// Keeps a prepared code's index pending and moves the next index above it.
    ///
    /// - Parameter code: The prepared code's index and date.
    mutating func hold(_ code: PendingRedeemCode) {
        pending.removeAll { $0.index == code.index }
        pending.append(code)
        pending.sort { $0.index < $1.index }
        raiseNextIndex(above: code.index)
    }

    /// Forgets a pending index without lowering the next index.
    ///
    /// - Parameter index: The pending index.
    mutating func release(_ index: UInt32) {
        pending.removeAll { $0.index == index }
    }

    /// Removes the codes at indices.
    ///
    /// - Parameter indices: The indices to remove.
    mutating func remove(_ indices: Set<UInt32>) {
        records.removeAll { indices.contains($0.index) }
    }

    /// Adds the codes that a scan of the chain found, keeping recorded codes at the same indices, and marks the ledger
    /// as discovered.
    ///
    /// - Parameter discovered: The ledger that the scan built.
    mutating func merge(_ discovered: RedeemCodeLedger) {
        for record in discovered.records where !records.contains(where: { $0.index == record.index }) { add(record) }
        nextIndex = max(nextIndex, discovered.nextIndex)
        isDiscovered = true
    }

    /// Applies what the indexer reports for the codes and pending indices.
    ///
    /// - Parameters:
    ///   - statuses: What the indexer reports, by index.
    ///   - reserves: The public lamports of pending indices' one-time accounts.
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
    ///
    /// - Parameter index: A used index.
    private mutating func raiseNextIndex(above index: UInt32) {
        let (above, overflow) = index.addingReportingOverflow(1)
        if !overflow { nextIndex = max(nextIndex, above) }
    }
}
