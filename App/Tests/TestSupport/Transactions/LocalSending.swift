import Foundation
import Transactions
@testable import RPC
@testable import widgets

@MainActor
struct LocalSending {
    let store: TransactionStore
    let records: StoredValue<[TransactionRecord]>
    let pending: StoredValue<Set<TransactionRecord.Key>>
    let account: widgets.Account
    let recipient: Address
    let sent: HTTPResponses
    let sockets: SocketSequence

    init(recovery: SigningRecoveryStore? = nil, statuses: [GetSignatureStatuses.Response] = [.status(.finalized)],
         height: UInt64 = 500, statusGate: Suspension? = nil, sockets: SocketSequence = SocketSequence(),
         sent: HTTPResponses = .sending(), fixture: SigningFixture? = nil,
         records: StoredValue<[TransactionRecord]> = StoredValue(),
         otherRecords: [TransactionRecord.Key: StoredValue<[TransactionRecord]>] = [:],
         pending: StoredValue<Set<TransactionRecord.Key>> = StoredValue()) throws {
        let fixture = try fixture ?? SigningFixture()
        let coordinator = try LocalTransactions(fixture: fixture, recovery: recovery, statuses: statuses,
                                                height: height, statusGate: statusGate, sockets: sockets,
                                                sent: sent).coordinator
        var storages = otherRecords
        storages[TransactionRecord.Key(account: fixture.account.id, network: .devnet)] = records
        store = .inMemory(storages, pending: pending) { _ in coordinator }
        self.records = records
        self.pending = pending
        account = fixture.account
        recipient = fixture.transfer.accounts[1].address
        self.sent = sent
        self.sockets = sockets
    }

    var key: TransactionRecord.Key { TransactionRecord.Key(account: account.id, network: .devnet) }

    var payment: TransactionRecord.Kind { .payment(recipient: recipient, asset: .nativeSOL, amount: 1_000_000_000) }

    func simulate() async throws -> Simulation {
        try await store.coordinator(for: .devnet).transfer(1_000_000_000, of: .nativeSOL, using: account, to: recipient)
    }

    func send(settling: (any TransactionSettling)? = nil) async throws -> TransactionRecord {
        try await store.send(simulate(), as: payment, from: account, settling: settling)
    }

    func settle(_ record: TransactionRecord) async throws -> TransactionRecord.Status {
        let status = try await store.watch(record.id, for: key)
        await sockets.waitUntilClosed()
        return status
    }

    func savedOnly(_ record: TransactionRecord) async -> Bool {
        await records.value?.map(\.id) == [record.id]
    }

    static func payment(to recipient: Address? = nil) throws -> TransactionRecord.Kind {
        .payment(recipient: try recipient ?? Address("4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T"), asset: .nativeSOL,
                 amount: 1)
    }
}
