import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

/// Checks that the private balance's move action opens a move in the direction it's asked for.
@MainActor
struct PrivateBalanceMoveActionTests {
    /// A Portfolio tab's private-balance workflows and the action that opens moves, with private balances on and
    /// 1,000,000 lamports available.
    /// - Returns: The tab's workflows and the action, which offers 2 SOL of public balance.
    /// - Throws: A fixture error.
    private static func moveBalance() async throws
        -> (model: PrivateBalanceModel, moveBalance: PrivateBalanceMoveAction) {
        let account = try await PrivateBalanceFixtures.account()
        let store = try await PrivateBalanceFixtures.store(holding: .available, of: account)
        await store.refresh(account, on: .devnet)
        let model = PrivateBalanceModel()
        return (model, PrivateBalanceMoveAction(model: model, privateBalances: store, account: account,
                                                network: .devnet, publicLamports: 2_000_000_000))
    }

    /// Each direction opens a move of the SOL it can move: a deposit of the account's public SOL, or a withdrawal of
    /// the available private SOL.
    /// - Parameters:
    ///   - direction: Which balance the SOL leaves.
    ///   - balance: The SOL the move can add, as its payment shows it.
    @Test(arguments: [(BalanceMoveProposal.Direction.toPrivate, Decimal(2)),
                      (.toPublic, Decimal(string: "0.001")!)])
    func `Each direction opens a move of the SOL it can move`(direction: BalanceMoveProposal.Direction,
                                                               balance: Decimal) async throws {
        let (model, moveBalance) = try await Self.moveBalance()

        moveBalance(direction)

        let move = try #require(model.move)
        #expect(move.direction == direction)
        #expect(move.payment.token.balance == balance)
    }
}
