import Foundation
import Transactions
@testable import RPC
@testable import widgets

@MainActor
struct PendingPayment {
    let transactions: TransactionStore
    let record: TransactionRecord
    let sockets: SocketSequence

    init(from account: UUID, statuses: [GetSignatureStatuses.Response] = [.status(.finalized)],
         sockets: SocketSequence = SocketSequence()) throws {
        let fixture = try SigningFixture()
        self.sockets = sockets
        let coordinator = try LocalTransactions(fixture: fixture, statuses: statuses, sockets: sockets).coordinator
        record = .fixture(.payment, signature: "pending", account: account)
        transactions = .inMemory(StoredValue([record])) { _ in coordinator }
    }

    func settle() async throws -> Outcome.Status {
        try await transactions.watch(record, untilClosed: sockets)
    }
}
