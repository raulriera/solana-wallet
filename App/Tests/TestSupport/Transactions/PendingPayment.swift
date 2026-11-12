import Foundation
import Transactions
@testable import RPC
@testable import widgets

@MainActor
struct PendingPayment {
    let transactions: TransactionStore
    let record: TransactionRecord
    let sockets: SocketSequence

    init(from account: UUID, to recipient: Address? = nil,
         statuses: [GetSignatureStatuses.Response] = [.status(.finalized)],
         sockets: SocketSequence = SocketSequence()) throws {
        let fixture = try SigningFixture()
        self.sockets = sockets
        let coordinator = try LocalTransactions(fixture: fixture, statuses: statuses, sockets: sockets).coordinator
        record = .fixture(.payment(recipient: recipient ?? fixture.transfer.accounts[1].address, mint: nil, units: 1),
                          signature: "pending", account: account)
        transactions = .inMemory([record.key: StoredValue([record])], pending: StoredValue([record.key])) { _ in
            coordinator
        }
    }

    func settle() async throws -> TransactionRecord.Status {
        let status = try await transactions.watch(record.id, for: record.key)
        await sockets.waitUntilClosed()
        return status
    }
}
