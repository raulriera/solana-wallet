import SwiftUI
import Testing
import Transactions
@testable import widgets

/// Checks that the keypad's Review button opens the move's review and starts proving and simulating it.
@MainActor
struct BalanceMoveReviewActionTests {
    /// Holds what the action opens, as the move's sheet does.
    @MainActor
    private final class Presented {
        var review: TransactionReviewModel<BalanceMoveProposal>?
        var presented: TransactionReviewModel<BalanceMoveProposal>?
        var error: PrivateBalanceError?
    }

    /// Reviewing a typed amount opens its review at once and starts preparing it.
    /// - Throws: A fixture error.
    @Test func `Reviewing opens the review and starts preparing it`() async throws {
        let presented = Presented()
        let move = try await Self.move()
        move.payment.press(.digit(1))

        Self.action(for: move, presented: presented)()

        let review = try #require(presented.review)
        #expect(presented.presented === review)
        #expect(review.attempt?.work == .review)
        #expect(review.proposal.direction == .toPrivate)
        #expect(review.proposal.amount.quantity == 1)
        #expect(presented.error == nil)
    }

    /// A review that shows keeps showing; once it closed, the next Review replaces the review that stayed.
    /// - Throws: A fixture error.
    @Test func `Reviewing again replaces only a closed review`() async throws {
        let presented = Presented()
        let move = try await Self.move()
        move.payment.press(.digit(1))
        let action = Self.action(for: move, presented: presented)
        action()
        let first = try #require(presented.review)

        action()
        #expect(presented.review === first)

        presented.presented = nil
        action()

        #expect(presented.review !== first)
        #expect(presented.presented === presented.review)
    }

    /// Nothing can't be moved, so reviewing an empty amount opens nothing.
    /// - Throws: A fixture error.
    @Test func `Reviewing an empty amount opens nothing`() async throws {
        let presented = Presented()

        Self.action(for: try await Self.move(), presented: presented)()

        #expect(presented.review == nil)
        #expect(presented.presented == nil)
    }

    /// A network without a transaction coordinator explains that the move can't be prepared instead of opening a
    /// review.
    /// - Throws: A fixture error.
    @Test func `Unavailable transactions explain the failure`() async throws {
        let presented = Presented()
        let move = try await Self.move(transactions: .inMemory { _ in throw SubmitterError.noProviders })
        move.payment.press(.digit(1))

        Self.action(for: move, presented: presented)()

        #expect(presented.review == nil)
        #expect(presented.presented == nil)
        #expect(presented.error == .preparationFailed)
    }

    /// A deposit of 2 SOL of public balance, opened from a private balance that's on.
    /// - Parameter transactions: The shared transactions, whose coordinator never leaves the process by default.
    /// - Returns: The move, with nothing typed.
    /// - Throws: A fixture error, or a test failure when no move opens.
    private static func move(transactions: TransactionStore = .unused) async throws -> BalanceMove {
        let account = try await PrivateBalanceFixtures.account()
        let model = try PrivateBalanceModel.fixture(
            HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]),
            keys: StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)]),
            transactions: transactions
        )
        await model.refresh(for: account)
        model.addToPrivateBalance(publicLamports: 2_000_000_000)
        return try #require(model.move)
    }

    /// Creates the action for a move, as its sheet does.
    /// - Parameters:
    ///   - move: The open move.
    ///   - presented: Receives what the action opens.
    /// - Returns: The action.
    private static func action(for move: BalanceMove, presented: Presented) -> BalanceMoveReviewAction {
        BalanceMoveReviewAction(move: move,
                                review: Binding { presented.review } set: { presented.review = $0 },
                                presented: Binding { presented.presented } set: { presented.presented = $0 },
                                error: Binding { presented.error } set: { presented.error = $0 })
    }
}
