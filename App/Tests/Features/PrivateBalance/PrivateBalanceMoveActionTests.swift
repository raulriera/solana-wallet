import Foundation
import Portfolio
import RPC
import Testing
import Transactions
@testable import widgets

@MainActor
struct PrivateBalanceMoveActionTests {
    private static let sol = Holding(
        asset: .nativeSOL,
        balance: TokenAmount(amount: 2_000_000_000, decimals: 9),
        imageURL: nil,
        valuation: nil
    )

    private static func moveBalance() async throws
        -> (model: PrivateBalanceModel, moveBalance: PrivateBalanceMoveAction) {
        let account = try await PrivateBalanceFixtures.account()
        let store = try await PrivateBalanceFixtures.store(holding: .available, of: account)
        await store.refresh(account, on: .devnet)
        let model = PrivateBalanceModel()
        return (
            model,
            PrivateBalanceMoveAction(
                model: model,
                privateBalances: store,
                account: account,
                network: .devnet,
                holding: Self.sol
            )
        )
    }

    @Test(arguments: [
        (BalanceMoveProposal.Direction.toPrivate, Decimal(2)),
        (.toPublic, Decimal(string: "0.001")!),
    ])
    func `Each direction opens a move of the amount it can move`(
        direction: BalanceMoveProposal.Direction,
        balance: Decimal
    ) async throws {
        let (model, moveBalance) = try await Self.moveBalance()

        moveBalance(direction)

        let move = try #require(model.move)
        #expect(move.direction == direction)
        #expect(Decimal(move.payment.token.balance) == balance)
    }
}
