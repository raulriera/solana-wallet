import Foundation
@testable import RPC
import Transactions
@testable import widgets

/// A sent devnet payment that the shared transactions keep as pending and list in their pending index, whose watch
/// settles through the real transaction coordinator over local responses and sockets.
@MainActor
struct PendingPayment {
    /// The shared transactions, which keep only ``record``.
    let transactions: TransactionStore
    /// The pending payment's record.
    let record: TransactionRecord
    /// The connections of the coordinator's watch.
    let sockets: SocketSequence

    /// Saves a pending payment whose watch reads the given statuses.
    /// - Parameters:
    ///   - account: The identifier of the account that sent the payment.
    ///   - recipient: Who the payment went to, or `nil` for the signing fixture's recipient.
    ///   - statuses: The watch's status reads, in arrival order.
    ///   - sockets: The watch's connections.
    /// - Throws: A fixture error.
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

    /// Waits for the payment to settle, then for its watch's connections to close.
    /// - Returns: The settled status.
    /// - Throws: The watch's error.
    func settle() async throws -> TransactionRecord.Status {
        let status = try await transactions.watch(record.id, for: record.key)
        await sockets.waitUntilClosed()
        return status
    }
}
