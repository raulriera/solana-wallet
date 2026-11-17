import Foundation
import Portfolio
import RPC
import Testing
import Transactions
@testable import widgets

@MainActor
struct PrivateBalanceMoveActionTests {
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
                holding: PrivateBalanceFixtures.solHolding
            )
        )
    }

    @Test
    func `Moving to public opens a move of the amount it can move`() async throws {
        let (model, moveBalance) = try await Self.moveBalance()

        moveBalance(.toPublic)

        let move = try #require(model.move)
        #expect(move.direction == .toPublic)
        #expect(Decimal(move.payment.token.balance) == Decimal(string: "0.001"))
    }
}
