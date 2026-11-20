import Portfolio
import RPC
import SwiftUI
import Testing
import Transactions
@testable import widgets

@MainActor
struct BalanceMoveReviewActionTests {
    @MainActor
    private final class Presented {
        var presented: TransactionReviewModel<BalanceMoveProposal>?
        var error: PrivateBalanceError?
    }

    @Test func `Reviewing opens the review and starts preparing it`() async throws {
        let presented = Presented()
        let move = try await Self.move()
        move.payment.press(.digit(1))

        Self.action(for: move, presented: presented)()

        let review = try #require(presented.presented)
        #expect(review.attempt?.work == .review)
        #expect(review.proposal.direction == .toPrivate)
        #expect(Decimal(review.proposal.sent) == 1)
        #expect(presented.error == nil)
    }

    @Test func `Reviewing again replaces only a closed review`() async throws {
        let presented = Presented()
        let move = try await Self.move()
        move.payment.press(.digit(1))
        let action = Self.action(for: move, presented: presented)
        action()
        let first = try #require(presented.presented)

        action()
        #expect(presented.presented === first)

        presented.presented = nil
        action()

        let second = try #require(presented.presented)
        #expect(second !== first)
    }

    @Test func `Reviewing an empty amount opens nothing`() async throws {
        let presented = Presented()

        Self.action(for: try await Self.move(), presented: presented)()

        #expect(presented.presented == nil)
    }

    @Test func `Unavailable transactions explain the failure`() async throws {
        let presented = Presented()
        let move = try await Self.move(transactions: .inMemory { _ in throw TransactionCoordinatorError.unsupportedNetwork })
        move.payment.press(.digit(1))

        Self.action(for: move, presented: presented)()

        #expect(presented.presented == nil)
        #expect(presented.error == .preparationFailed)
    }

    private static func move(transactions: TransactionStore = .unused) async throws -> BalanceMove {
        let account = try await PrivateBalanceFixtures.account()
        let store = try PrivateBalanceStore.fixture(
            HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]),
            keys: StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)]),
            transactions: transactions
        )
        let model = PrivateBalanceModel()
        await store.refresh(account, on: .devnet)
        model.open(.toPrivate, of: PrivateBalanceFixtures.solHolding, in: store, for: account, on: .devnet)
        return try #require(model.sheet?.move)
    }

    private static func action(for move: BalanceMove, presented: Presented) -> BalanceMoveReviewAction {
        BalanceMoveReviewAction(move: move,
                                presented: Binding { presented.presented } set: { presented.presented = $0 },
                                error: Binding { presented.error } set: { presented.error = $0 })
    }
}
