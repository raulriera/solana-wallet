import Foundation
import Privacy
import RPC
import Testing
import Transactions
@testable import widgets

@MainActor
struct BalanceMoveTests {
    @Test(arguments: [
        (BalanceMoveProposal.Direction.toPrivate, PaymentModel.Source.publicBalance),
        (.toPublic, .privateBalance),
    ])
    func `A move types from the balance that it leaves`(
        direction: BalanceMoveProposal.Direction,
        source: PaymentModel.Source
    ) async throws {
        let move = try await Self.move(direction)

        #expect(move.payment.source == source)
        #expect(move.payment.quantity == 0)
    }

    @Test
    func `A review proposes the asset of the move's token`() async throws {
        let move = try await Self.move(.toPublic, mint: try PrivateToken.devnetUSDC.mint)
        move.payment.press(.digit(1))

        #expect(try move.review().proposal.asset == .token(.devnetUSDC))
    }

    @Test
    func `A token that private balances don't hold opens no move`() async throws {
        let move = try await Self.optionalMove(.toPrivate, mint: Address("So11111111111111111111111111111111111111112"))

        #expect(move == nil)
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

    private static func move(
        _ direction: BalanceMoveProposal.Direction,
        mint: Address? = nil,
        transactions: TransactionStore = .unused
    ) async throws -> BalanceMove {
        try #require(await optionalMove(direction, mint: mint, transactions: transactions))
    }

    private static func optionalMove(
        _ direction: BalanceMoveProposal.Direction,
        mint: Address?,
        transactions: TransactionStore = .unused
    ) async throws -> BalanceMove? {
        let balances = PrivateBalances.inMemory(
            keys: StoredValue(),
            notes: StoredValue(),
            recovery: try PrivateBalanceFixtures.recoveryStore(),
            responses: HTTPResponses([:])
        )
        let token = PaymentToken(
            mint: mint,
            symbol: "SOL",
            balance: Decimal(string: "1.5") ?? 0,
            price: nil,
            decimals: 9
        )
        return BalanceMove(
            direction: direction,
            token: token,
            account: try await PrivateBalanceFixtures.account(),
            network: .devnet,
            balances: balances,
            transactions: transactions
        )
    }
}
