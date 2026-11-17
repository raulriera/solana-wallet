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
    func `A review of an amount that can't be sent fails`() async throws {
        let move = try await Self.move(.toPublic, asset: .nativeSOL)

        #expect(throws: PrivateBalanceError.preparationFailed) { try move.review() }
    }

    private static func move(_ direction: BalanceMoveProposal.Direction, asset: Asset) async throws -> BalanceMove {
        let balances = PrivateBalances.inMemory(
            keys: StoredValue(),
            notes: StoredValue(),
            recovery: try PrivateBalanceFixtures.recoveryStore(),
            responses: HTTPResponses([:])
        )
        let balance =
            switch asset {
            case .nativeSOL: TokenAmount(lamports: 1_500_000_000)
            case .token(let mint): TokenAmount(amount: 1_500_000, decimals: mint.decimals)
            }
        let token = PaymentToken(asset: asset, balance: balance, price: nil)
        return BalanceMove(
            direction: direction,
            token: token,
            privateAsset: try #require(PrivateAsset(asset.id)),
            account: try await PrivateBalanceFixtures.account(),
            network: .devnet,
            balances: balances,
            transactions: .unused
        )
    }
}
