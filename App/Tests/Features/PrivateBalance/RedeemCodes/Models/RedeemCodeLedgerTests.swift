import Foundation
import Testing
@testable import widgets

/// Verifies how an account's codes entry adds, holds, removes, merges, and reconciles codes, and keeps its next index
/// above them.
struct RedeemCodeLedgerTests {
    /// Adding a code keeps the codes by index and moves the next index above the highest one.
    @Test
    func `Added codes stay in index order below the next index`() {
        var ledger = RedeemCodeLedger(isDiscovered: false)

        ledger.add(Self.record(at: 4))
        ledger.add(Self.record(at: 1))

        #expect(ledger.records.map(\.index) == [1, 4])
        #expect(ledger.nextIndex == 5)
    }

    /// A code at an index already kept replaces the kept one.
    @Test
    func `A code at a kept index replaces it`() {
        var ledger = RedeemCodeLedger(records: [Self.record(at: 2)], isDiscovered: true)

        ledger.add(Self.record(at: 2, amount: 9))

        #expect(ledger.records == [Self.record(at: 2, amount: 9)])
    }

    /// Removing codes keeps the next index, so their indices are never used again.
    @Test
    func `Removed codes keep the next index`() {
        var ledger = RedeemCodeLedger(records: [Self.record(at: 0), Self.record(at: 3)], isDiscovered: true)

        ledger.remove([3])

        #expect(ledger.records == [Self.record(at: 0)])
        #expect(ledger.nextIndex == 4)
    }

    /// Merging a scan keeps recorded codes, adds the found ones, raises the next index, and marks the entry discovered.
    @Test
    func `Merging a scan keeps recorded codes and adds found ones`() {
        var ledger = RedeemCodeLedger(records: [Self.record(at: 6, amount: 1)], isDiscovered: false)

        ledger.merge(RedeemCodeLedger(records: [Self.record(at: 2), Self.record(at: 6, amount: 2)], nextIndex: 9,
                                      isDiscovered: true))

        #expect(ledger.records == [Self.record(at: 2), Self.record(at: 6, amount: 1)])
        #expect(ledger.nextIndex == 9)
        #expect(ledger.isDiscovered)
    }

    /// A record at the highest index doesn't overflow the next index.
    @Test
    func `The highest index keeps the next index`() {
        var ledger = RedeemCodeLedger(nextIndex: 3, isDiscovered: true)

        ledger.add(Self.record(at: .max))

        #expect(ledger.nextIndex == 3)
    }

    /// A held index stays pending and moves the next index above it, so no later code takes it.
    @Test
    func `Held indices stay pending below the next index`() {
        var ledger = RedeemCodeLedger(isDiscovered: false)

        ledger.hold(Self.pending(at: 3))

        #expect(ledger.pending == [Self.pending(at: 3)])
        #expect(ledger.records.isEmpty)
        #expect(ledger.nextIndex == 4)
    }

    /// A recorded code replaces the pending index of its preparation.
    @Test
    func `A recorded code replaces its pending index`() {
        var ledger = RedeemCodeLedger(pending: [Self.pending(at: 0), Self.pending(at: 1)], isDiscovered: false)

        ledger.add(Self.record(at: 1))

        #expect(ledger.pending == [Self.pending(at: 0)])
        #expect(ledger.records == [Self.record(at: 1)])
    }

    /// A released index leaves the pending indices and keeps the next index, so it's never used again.
    @Test
    func `Released indices keep the next index`() {
        var ledger = RedeemCodeLedger(pending: [Self.pending(at: 2)], isDiscovered: true)

        ledger.release(2)

        #expect(ledger.pending.isEmpty)
        #expect(ledger.nextIndex == 3)
    }

    /// The indexer decides each code: unspent notes keep it with their amount, a funding not indexed yet keeps it as it
    /// is, and spent notes drop it.
    @Test
    func `Codes follow the indexer`() {
        var ledger = RedeemCodeLedger(records: [Self.record(at: 0), Self.record(at: 1), Self.record(at: 2)],
                                      isDiscovered: true)

        ledger.reconcile(with: [0: .unspent(lamports: 700, signature: "other"), 1: .unfunded, 2: .spent],
                         reserves: [:], at: Self.now)

        #expect(ledger.records == [Self.record(at: 0, amount: 700), Self.record(at: 1)])
    }

    /// A pending index with unspent notes becomes a code with their amount, the funding's signature, its one-time
    /// account's lamports as the reserve, and its preparation's date.
    @Test
    func `Pending indices with unspent notes become codes`() {
        var ledger = RedeemCodeLedger(pending: [Self.pending(at: 4)], isDiscovered: true)

        ledger.reconcile(with: [4: .unspent(lamports: 900, signature: "landed")], reserves: [4: 12], at: Self.now)

        #expect(ledger.pending.isEmpty)
        #expect(ledger.records == [RedeemCodeRecord(index: 4, amount: 900, reserve: 12, created: Self.now,
                                                    fundingSignature: "landed")])
    }

    /// A pending index without unspent notes stays while its funding could still land, and leaves once it can't.
    @Test
    func `Pending indices without notes leave once expired`() {
        let expired = PendingRedeemCode(index: 5, created: Self.now.addingTimeInterval(-3_601))
        let spent = PendingRedeemCode(index: 6, created: Self.now.addingTimeInterval(-3_601))
        var ledger = RedeemCodeLedger(pending: [Self.pending(at: 4), expired, spent], isDiscovered: true)

        ledger.reconcile(with: [4: .unfunded, 5: .unfunded, 6: .spent], reserves: [:], at: Self.now)

        #expect(ledger.pending == [Self.pending(at: 4)])
        #expect(ledger.records.isEmpty)
        #expect(ledger.nextIndex == 7)
    }

    /// Codes and pending indices without a status, such as those recorded while the indexer was read, stay.
    @Test
    func `Indices without a status stay`() {
        let expired = PendingRedeemCode(index: 5, created: Self.now.addingTimeInterval(-3_601))
        let ledger = RedeemCodeLedger(records: [Self.record(at: 1)], pending: [expired], isDiscovered: true)
        var reconciled = ledger

        reconciled.reconcile(with: [:], reserves: [:], at: Self.now)

        #expect(reconciled == ledger)
    }

    /// An entry decodes to the same codes, pending indices, next index, and discovery.
    @Test
    func `Entries round trip`() throws {
        let ledger = RedeemCodeLedger(records: [Self.record(at: 1)], pending: [Self.pending(at: 2)], nextIndex: 5,
                                      isDiscovered: true)

        #expect(try JSONDecoder().decode(RedeemCodeLedger.self, from: JSONEncoder().encode(ledger)) == ledger)
    }

    /// The current date of every reconciliation.
    private static let now = Date(timeIntervalSince1970: 1_000_000)

    /// Creates an index that a preparation took at ``now``.
    /// - Parameter index: The index.
    /// - Returns: The pending index.
    private static func pending(at index: UInt32) -> PendingRedeemCode {
        PendingRedeemCode(index: index, created: now)
    }

    /// Creates a code's record.
    /// - Parameters:
    ///   - index: The code's index.
    ///   - amount: The code's amount.
    /// - Returns: The record.
    private static func record(at index: UInt32, amount: UInt64 = 1_000) -> RedeemCodeRecord {
        RedeemCodeRecord(index: index, amount: amount, reserve: 10, created: Date(timeIntervalSince1970: 0),
                         fundingSignature: "funding")
    }
}
