import Foundation
import Testing
@testable import widgets

struct RedeemCodeLedgerTests {
    @Test
    func `Added codes stay in index order below the next index`() {
        var ledger = RedeemCodeLedger(isDiscovered: false)

        ledger.add(Self.record(at: 4))
        ledger.add(Self.record(at: 1))

        #expect(ledger.records.map(\.index) == [1, 4])
        #expect(ledger.nextIndex == 5)
    }

    @Test
    func `A code at a kept index replaces it`() {
        var ledger = RedeemCodeLedger(records: [Self.record(at: 2)], isDiscovered: true)

        ledger.add(Self.record(at: 2, amount: 9))

        #expect(ledger.records == [Self.record(at: 2, amount: 9)])
    }

    @Test
    func `Removed codes keep the next index`() {
        var ledger = RedeemCodeLedger(records: [Self.record(at: 0), Self.record(at: 3)], isDiscovered: true)

        ledger.remove([3])

        #expect(ledger.records == [Self.record(at: 0)])
        #expect(ledger.nextIndex == 4)
    }

    @Test
    func `Merging a scan keeps recorded codes and adds found ones`() {
        var ledger = RedeemCodeLedger(records: [Self.record(at: 6, amount: 1)], isDiscovered: false)

        ledger.merge(RedeemCodeLedger(records: [Self.record(at: 2), Self.record(at: 6, amount: 2)], nextIndex: 9,
                                      isDiscovered: true))

        #expect(ledger.records == [Self.record(at: 2), Self.record(at: 6, amount: 1)])
        #expect(ledger.nextIndex == 9)
        #expect(ledger.isDiscovered)
    }

    @Test
    func `Merging a scan that isn't discovered keeps the ledger undiscovered`() {
        var ledger = RedeemCodeLedger(isDiscovered: false)

        ledger.merge(RedeemCodeLedger(nextIndex: 4, isDiscovered: false))

        #expect(!ledger.isDiscovered)
        #expect(ledger.nextIndex == 4)
    }

    @Test
    func `The highest index keeps the next index`() {
        var ledger = RedeemCodeLedger(nextIndex: 3, isDiscovered: true)

        ledger.add(Self.record(at: .max))

        #expect(ledger.nextIndex == 3)
    }

    @Test
    func `Held indices stay pending below the next index`() {
        var ledger = RedeemCodeLedger(isDiscovered: false)

        ledger.hold(Self.pending(at: 3))

        #expect(ledger.pending == [Self.pending(at: 3)])
        #expect(ledger.records.isEmpty)
        #expect(ledger.nextIndex == 4)
    }

    @Test
    func `A recorded code replaces its pending index`() {
        var ledger = RedeemCodeLedger(pending: [Self.pending(at: 0), Self.pending(at: 1)], isDiscovered: false)

        ledger.add(Self.record(at: 1))

        #expect(ledger.pending == [Self.pending(at: 0)])
        #expect(ledger.records == [Self.record(at: 1)])
    }

    @Test
    func `Released indices keep the next index`() {
        var ledger = RedeemCodeLedger(pending: [Self.pending(at: 2)], isDiscovered: true)

        ledger.release(2)

        #expect(ledger.pending.isEmpty)
        #expect(ledger.nextIndex == 3)
    }

    @Test
    func `Codes follow the indexer`() {
        var ledger = RedeemCodeLedger(records: [Self.record(at: 0), Self.record(at: 1), Self.record(at: 2)],
                                      isDiscovered: true)

        ledger.reconcile(with: [0: .unspent(lamports: 700, signature: "other"), 1: .unfunded, 2: .spent],
                         lamports: [0: 12, 1: 12, 2: 9], at: Self.now)

        #expect(ledger.records == [Self.record(at: 0, amount: 700), Self.record(at: 1)])
    }

    @Test(arguments: [[1: 10, 5: 12], [:]] as [[UInt32: UInt64]])
    func `Spent codes whose reserve may be intact stay`(lamports: [UInt32: UInt64]) {
        let expired = PendingRedeemCode(index: 5, created: Self.now.addingTimeInterval(-3_601))
        let ledger = RedeemCodeLedger(records: [Self.record(at: 1)], pending: [expired], isDiscovered: true)
        var reconciled = ledger

        reconciled.reconcile(with: [1: .spent, 5: .spent], lamports: lamports, at: Self.now)

        #expect(reconciled == ledger)
    }

    @Test
    func `Pending indices with unspent notes become codes`() {
        var ledger = RedeemCodeLedger(pending: [Self.pending(at: 4)], isDiscovered: true)

        ledger.reconcile(with: [4: .unspent(lamports: 900, signature: "landed")], lamports: [4: 12], at: Self.now)

        #expect(ledger.pending.isEmpty)
        #expect(ledger.records == [RedeemCodeRecord(index: 4, amount: 900, reserve: 12, created: Self.now,
                                                    fundingSignature: "landed")])
    }

    @Test
    func `Pending indices without notes leave once expired`() {
        let expired = PendingRedeemCode(index: 5, created: Self.now.addingTimeInterval(-3_601))
        let spent = PendingRedeemCode(index: 6, created: Self.now.addingTimeInterval(-3_601))
        var ledger = RedeemCodeLedger(pending: [Self.pending(at: 4), expired, spent], isDiscovered: true)

        ledger.reconcile(with: [4: .unfunded, 5: .unfunded, 6: .spent], lamports: [6: 0], at: Self.now)

        #expect(ledger.pending == [Self.pending(at: 4)])
        #expect(ledger.records.isEmpty)
        #expect(ledger.nextIndex == 7)
    }

    @Test
    func `Codes and pending indices with unconfirmed notes stay`() {
        let expired = PendingRedeemCode(index: 5, created: Self.now.addingTimeInterval(-3_601))
        let ledger = RedeemCodeLedger(records: [Self.record(at: 1)], pending: [expired], isDiscovered: true)
        var reconciled = ledger

        reconciled.reconcile(with: [1: .unconfirmed, 5: .unconfirmed], lamports: [:], at: Self.now)

        #expect(reconciled == ledger)
    }

    @Test
    func `Indices without a status stay`() {
        let expired = PendingRedeemCode(index: 5, created: Self.now.addingTimeInterval(-3_601))
        let ledger = RedeemCodeLedger(records: [Self.record(at: 1)], pending: [expired], isDiscovered: true)
        var reconciled = ledger

        reconciled.reconcile(with: [:], lamports: [:], at: Self.now)

        #expect(reconciled == ledger)
    }

    @Test
    func `Entries round trip`() throws {
        let ledger = RedeemCodeLedger(records: [Self.record(at: 1)], pending: [Self.pending(at: 2)], nextIndex: 5,
                                      isDiscovered: true)

        #expect(try JSONDecoder().decode(RedeemCodeLedger.self, from: JSONEncoder().encode(ledger)) == ledger)
    }

    private static let now = Date(timeIntervalSince1970: 1_000_000)

    private static func pending(at index: UInt32) -> PendingRedeemCode {
        PendingRedeemCode(index: index, created: now)
    }

    private static func record(at index: UInt32, amount: UInt64 = 1_000) -> RedeemCodeRecord {
        RedeemCodeRecord(index: index, amount: amount, reserve: 10, created: Date(timeIntervalSince1970: 0),
                         fundingSignature: "funding")
    }
}
