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
        let move = try await Self.move(direction, asset: .nativeSOL)

        #expect(move.payment.source == source)
        #expect(move.payment.quantity == 0)
    }

    @Test
    func `A review proposes the asset of the move's token`() async throws {
        let usdc = Mint.fixture(PrivateToken.devnetUSDC.mint.value, decimals: 6)
        let move = try await Self.move(.toPublic, asset: .token(usdc))
        move.payment.press(.digit(1))

        #expect(try move.review().proposal.asset == .token(usdc))
    }

    @Test
    func `A token that private balances don't hold opens no move`() async throws {
        let wrapped = Mint.fixture("So11111111111111111111111111111111111111112", decimals: 9)
        let move = try await Self.optionalMove(.toPrivate, asset: .token(wrapped))

        #expect(move == nil)
    }

    @Test
    func `A review freezes the typed amount`() async throws {
        let move = try await Self.move(.toPublic, asset: .nativeSOL)
        move.payment.press(.digit(1))

        let review = try move.review()
        move.payment.press(.digit(2))

        #expect(review.proposal.direction == .toPublic)
        #expect(Decimal(review.proposal.sent) == 1)
        #expect(review.review == nil)
        #expect(review.attempt == nil)
    }

    @Test
    func `A review fails without a transaction coordinator`() async throws {
        let move = try await Self.move(.toPrivate, asset: .nativeSOL, transactions: .inMemory { _ in throw TransactionCoordinatorError.unsupportedNetwork })
        move.payment.press(.digit(1))

        #expect(throws: TransactionCoordinatorError.unsupportedNetwork) { try move.review() }
    }

    @Test
    func `A review of an amount that can't be sent fails`() async throws {
        let move = try await Self.move(.toPublic, asset: .nativeSOL)

        #expect(throws: PrivateBalanceError.preparationFailed) { try move.review() }
    }

    private static func move(
        _ direction: BalanceMoveProposal.Direction,
        asset: Asset,
        transactions: TransactionStore = .unused
    ) async throws -> BalanceMove {
        try #require(await optionalMove(direction, asset: asset, transactions: transactions))
    }

    private static func optionalMove(
        _ direction: BalanceMoveProposal.Direction,
        asset: Asset,
        transactions: TransactionStore = .unused
    ) async throws -> BalanceMove? {
        let balances = PrivateBalances.inMemory(
            keys: StoredValue(),
            notes: StoredValue(),
            recovery: try PrivateBalanceFixtures.recoveryStore(),
            responses: HTTPResponses([:])
        )
        let token = PaymentToken(asset: asset, balance: TokenAmount(amount: 1_500_000_000, decimals: 9), price: nil)
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
