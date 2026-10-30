import RPC
import Testing
import Transactions
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TransactionReviewModelBalanceMoveTests {
    @Test
    func `A review that isn't approved isn't committed`() async throws {
        let deposit = try await LocalBalanceMove.deposit()

        try await deposit.model.runReview()

        #expect(!deposit.model.isCommitted)
    }

    @Test
    func `Approving commits the move before it's recorded`() async throws {
        let deposit = try await LocalBalanceMove.deposit()
        try await deposit.model.runReview()

        deposit.model.approve()

        #expect(deposit.model.record == nil)
        #expect(deposit.model.isCommitted)
    }

    @Test
    func `A sent move stays committed`() async throws {
        let deposit = try await LocalBalanceMove.deposit(statuses: [.status(.finalized)])
        try await deposit.model.runReview()

        let record = try await deposit.model.runApproval()

        #expect(deposit.model.isCommitted)
        #expect(try await deposit.transactions.watch(record.id, for: record.key) == .succeeded)
        #expect(deposit.model.isCommitted)
        await deposit.sockets.waitUntilClosed()
    }

    @Test
    func `A dropped move isn't committed`() async throws {
        let deposit = try await LocalBalanceMove.deposit(statuses: [.status(nil)], height: 600)
        try await deposit.model.runReview()
        let record = try await deposit.model.runApproval()

        #expect(await deposit.transactions.settledStatus(of: record) == .dropped)

        #expect(!deposit.model.isCommitted)
        await deposit.sockets.waitUntilClosed()
    }
}
