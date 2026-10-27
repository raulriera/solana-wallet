import RPC
import Testing
import Transactions
@testable import widgets

/// Checks when a private move's review used up its typed amount, which closes the move's keypad.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TransactionReviewModelBalanceMoveTests {
    /// A reviewed move that isn't approved keeps its amount.
    @Test
    func `A review that isn't approved isn't committed`() async throws {
        let deposit = try await LocalBalanceMove.deposit()

        try await deposit.model.runReview()

        #expect(!deposit.model.isCommitted)
    }

    /// Approving commits the move at once, before it's recorded, so a review that closes while the move is signed and
    /// sent still uses up the amount.
    @Test
    func `Approving commits the move before it's recorded`() async throws {
        let deposit = try await LocalBalanceMove.deposit()
        try await deposit.model.runReview()

        deposit.model.approve()

        #expect(deposit.model.record == nil)
        #expect(deposit.model.isCommitted)
    }

    /// A sent move stays committed while it's pending and once it lands.
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

    /// A dropped move never left the account, so its amount can be reviewed again.
    @Test
    func `A dropped move isn't committed`() async throws {
        // The epoch's block height is past the blockhash's last valid block height, 550, and no status exists.
        let deposit = try await LocalBalanceMove.deposit(statuses: [.status(nil)], height: 600)
        try await deposit.model.runReview()
        let record = try await deposit.model.runApproval()

        #expect(await deposit.transactions.settledStatus(of: record) == .dropped)

        #expect(!deposit.model.isCommitted)
        await deposit.sockets.waitUntilClosed()
    }
}
