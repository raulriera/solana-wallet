import Foundation
import Transactions
@testable import RPC
@testable import widgets

@MainActor
struct PendingMove {
    let transactions: TransactionStore
    let record: TransactionRecord
    let sockets = SocketSequence()

    init(_ kind: TransactionRecord.Kind = .privateDeposit, from account: UUID) throws {
        let coordinator = try LocalTransactions(fixture: SigningFixture(), statuses: [.status(.finalized)],
                                                sockets: sockets).coordinator
        record = .fixture(kind, signature: "pending", account: account)
        transactions = .inMemory(StoredValue([record])) { _ in coordinator }
    }

    func settle() async throws -> TransactionOutcome {
        let status = try await transactions.watch(record.id, for: record.key)
        await sockets.waitUntilClosed()
        return status
    }
}
