import Foundation
@testable import RPC
import Transactions
@testable import widgets

/// A sent devnet move between an account's balances that the shared transactions keep as pending, whose watch settles
/// through the real transaction coordinator over local responses and sockets.
@MainActor
struct PendingMove {
    /// The shared transactions, which keep only ``record``.
    let transactions: TransactionStore
    /// The pending move's record.
    let record: TransactionRecord
    /// The connections of the coordinator's watch.
    let sockets = SocketSequence()

    /// Saves a pending move whose watch finds it finalized.
    /// - Parameters:
    ///   - kind: The private deposit or withdrawal; by default, a deposit of 1,000,000 lamports.
    ///   - account: The identifier of the account that sent the move.
    /// - Throws: A fixture error.
    init(_ kind: TransactionRecord.Kind = .privateDeposit(lamports: 1_000_000), from account: UUID) throws {
        let coordinator = try LocalTransactions(fixture: SigningFixture(), statuses: [.status(.finalized)],
                                                sockets: sockets).coordinator
        record = .fixture(kind, signature: "pending", account: account)
        transactions = .inMemory([record.key: StoredValue([record])]) { _ in coordinator }
    }

    /// Waits for the move to settle, then for its watch's connections to close.
    /// - Returns: The settled status.
    /// - Throws: The watch's error.
    func settle() async throws -> TransactionRecord.Status {
        let status = try await transactions.watch(record.id, for: record.key)
        await sockets.waitUntilClosed()
        return status
    }
}
