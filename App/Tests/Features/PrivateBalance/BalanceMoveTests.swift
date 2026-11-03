import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

@MainActor
struct BalanceMoveTests {
    @Test(arguments: [(BalanceMoveProposal.Direction.toPrivate, PaymentModel.Source.publicBalance),
                      (.toPublic, .privateBalance)])
    func `A move types SOL from the balance that it leaves`(direction: BalanceMoveProposal.Direction,
                                                          source: PaymentModel.Source) async throws {
        let move = try await Self.move(direction)

        #expect(move.payment.source == source)
        #expect(move.payment.token.symbol == "SOL")
        #expect(move.payment.token.balance == Decimal(string: "1.5"))
        #expect(move.payment.quantity == 0)
    }

    @Test
    func `A review freezes the typed amount`() async throws {
        let move = try await Self.move(.toPublic)
        move.payment.press(.digit(1))

        let review = try move.review()
        move.payment.press(.digit(2))

        #expect(review.proposal.direction == .toPublic)
        #expect(review.proposal.amount.quantity == 1)
        #expect(review.review == nil)
        #expect(review.attempt == nil)
    }

    @Test
    func `A review fails without a transaction coordinator`() async throws {
        let move = try await Self.move(.toPrivate, transactions: .inMemory { _ in throw TransactionCoordinatorError.unsupportedNetwork })

        #expect(throws: TransactionCoordinatorError.unsupportedNetwork) { try move.review() }
    }

    private static func move(_ direction: BalanceMoveProposal.Direction,
                             transactions: TransactionStore = .unused) async throws -> BalanceMove {
        let balances = PrivateBalances.inMemory(keys: StoredValue(), notes: StoredValue(),
                                                recovery: try PrivateBalanceFixtures.recoveryStore(),
                                                responses: HTTPResponses([:]))
        return BalanceMove(direction: direction, account: try await PrivateBalanceFixtures.account(), network: .devnet,
                           spendableLamports: 1_500_000_000, balances: balances, transactions: transactions)
    }
}
