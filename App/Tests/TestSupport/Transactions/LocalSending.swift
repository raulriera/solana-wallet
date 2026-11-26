import Foundation
import Transactions
@testable import RPC
@testable import widgets

@MainActor
struct LocalSending {
    let store: TransactionStore
    let pending: StoredValue<[TransactionRecord]>
    let account: widgets.Account
    let recipient: Address
    let sent: HTTPResponses
    let sockets: SocketSequence

    init(recovery: SigningRecoveryStore? = nil, statuses: [GetSignatureStatuses.Response] = [.status(.finalized)],
         height: UInt64 = 500, statusGate: Suspension? = nil, sockets: SocketSequence = SocketSequence(),
         sent: HTTPResponses = .sending(), fixture: SigningFixture? = nil,
         pending: StoredValue<[TransactionRecord]> = StoredValue()) throws {
        let fixture = try fixture ?? SigningFixture()
        let coordinator = try LocalTransactions(fixture: fixture, recovery: recovery, statuses: statuses,
                                                height: height, statusGate: statusGate, sockets: sockets,
                                                sent: sent).coordinator
        store = .inMemory(pending) { _ in coordinator }
        self.pending = pending
        account = fixture.account
        recipient = fixture.transfer.accounts[1].address
        self.sent = sent
        self.sockets = sockets
    }

    var key: TransactionRecord.Key { TransactionRecord.Key(account: account.id, network: .devnet) }

    func simulate() async throws -> Simulation {
        try await store.coordinator(for: .devnet).transfer(1_000_000_000, of: .nativeSOL, using: account, to: recipient)
    }

    func send(settling: (any TransactionSettling)? = nil) async throws -> TransactionRecord {
        try await send(simulate(), settling: settling)
    }

    func send(_ simulation: Simulation, settling: (any TransactionSettling)? = nil) async throws -> TransactionRecord {
        try await store.send(simulation, as: .payment, from: account, settling: settling)
    }

    func settle(_ record: TransactionRecord) async throws -> TransactionOutcome.Status {
        try await store.watch(record, untilClosed: sockets)
    }
}
