import Testing
import Transactions
@testable import widgets

/// Checks that the review action starts preparing a move's review only once its amount can be moved.
@MainActor
struct BalanceMoveReviewActionTests {
    /// A deposit of 2 SOL of public balance, opened from a private balance that's on.
    /// - Returns: The move, with nothing typed.
    /// - Throws: A fixture error, or a test failure when no move opens.
    private static func move() async throws -> BalanceMoveModel {
        let account = try await PrivateBalanceFixtures.account()
        let model = try PrivateBalanceModel.fixture(
            HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]),
            keys: StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        )
        await model.refresh(for: account)
        model.addToPrivateBalance(publicLamports: 2_000_000_000)
        return try #require(model.move)
    }

    /// Reviewing a typed amount starts preparing the review.
    @Test func `Reviewing a typed amount starts preparing it`() async throws {
        let move = try await Self.move()
        move.payment.press(.digit(1))

        BalanceMoveReviewAction(move: move)()

        #expect(move.isWorking)
    }

    /// Nothing can't be moved, so reviewing an empty amount starts nothing.
    @Test func `Reviewing an empty amount starts nothing`() async throws {
        let move = try await Self.move()

        BalanceMoveReviewAction(move: move)()

        #expect(!move.isWorking)
    }
}
