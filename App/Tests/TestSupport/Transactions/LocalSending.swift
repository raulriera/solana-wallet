import Foundation
@testable import RPC
import Transactions
@testable import widgets

/// The shared transactions over in-memory records and pending index, whose devnet coordinator answers from local
/// responses and sockets, with what stands behind them.
///
/// Each transaction pays 1 SOL from the fixture account on devnet; its blockhash is valid through block height 550.
@MainActor
struct LocalSending {
    /// The store under test.
    let store: TransactionStore
    /// The in-memory records of the fixture account on devnet.
    let records: StoredValue<[TransactionRecord]>
    /// The in-memory pending index.
    let pending: StoredValue<Set<TransactionRecord.Key>>
    /// The account that sends.
    let account: widgets.Account
    /// The payment's recipient.
    let recipient: Address
    /// The responses that acknowledge each sent transaction.
    let sent: HTTPResponses
    /// The connections of the coordinator's watch.
    let sockets: SocketSequence

    /// Creates a store whose devnet coordinator answers from local responses and sockets.
    /// - Parameters:
    ///   - recovery: The recovery storage that signing reads, or `nil` for the fixture recovery.
    ///   - statuses: The watch's status reads, in arrival order.
    ///   - height: The finalized block height of the watch's epoch reads.
    ///   - statusGate: An optional suspension of the watch's status reads.
    ///   - sockets: The watch's connections.
    ///   - sent: The responses that acknowledge each sent transaction.
    ///   - fixture: The account and transaction to send, or `nil` for a new fixture.
    ///   - records: The in-memory records of the fixture account on devnet.
    ///   - otherRecords: The in-memory records of other keys; keys without any start with no records.
    ///   - pending: The in-memory pending index.
    /// - Throws: A fixture error.
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

    /// The account's records on devnet.
    var key: TransactionRecord.Key { TransactionRecord.Key(account: account.id, network: .devnet) }

    /// The payment that the fixture sends.
    var payment: TransactionRecord.Kind { .payment(recipient: recipient, mint: nil, units: 1_000_000_000) }

    /// Simulates the payment for review.
    /// - Returns: The simulation to send.
    /// - Throws: A simulation error.
    func simulate() async throws -> Simulation {
        try await store.coordinator(for: .devnet).transfer(1_000_000_000, using: account, to: recipient)
    }

    /// Simulates and sends the payment.
    /// - Parameter settling: What finishes the payment's work once it settles, if anything.
    /// - Returns: The pending record.
    /// - Throws: A simulation or sending error.
    func send(settling: (any TransactionSettling)? = nil) async throws -> TransactionRecord {
        try await store.send(simulate(), as: payment, from: account, settling: settling)
    }

    /// Waits for a sent record to settle, then for its watch's connections to close.
    /// - Parameter record: The sent record.
    /// - Returns: The settled status.
    /// - Throws: The watch's error.
    func settle(_ record: TransactionRecord) async throws -> TransactionRecord.Status {
        let status = try await store.watch(record.id, for: key)
        await sockets.waitUntilClosed()
        return status
    }

    /// Whether the in-memory records are exactly one record.
    /// - Parameter record: The record.
    /// - Returns: Whether it's the only saved record.
    func savedOnly(_ record: TransactionRecord) async -> Bool {
        await records.value?.map(\.id) == [record.id]
    }

    /// A 1-lamport SOL payment.
    /// - Parameter recipient: The recipient, or `nil` for a fixed address.
    /// - Returns: The payment.
    /// - Throws: A fixture error.
    static func payment(to recipient: Address? = nil) throws -> TransactionRecord.Kind {
        .payment(recipient: try recipient ?? Address("4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T"), mint: nil,
                 units: 1)
    }
}
