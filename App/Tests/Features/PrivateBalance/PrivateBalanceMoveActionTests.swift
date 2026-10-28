import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

/// Checks that the private balance's move action opens a move in the direction it's asked for.
@MainActor
struct PrivateBalanceMoveActionTests {
    /// A window's private-balance workflows, with private balances on and 1,000,000 lamports available.
    /// - Returns: The window's workflows and its account.
    /// - Throws: A fixture error.
    private static func model() async throws -> (model: PrivateBalanceModel, account: widgets.Account) {
        let account = try await PrivateBalanceFixtures.account()
        let store = try await PrivateBalanceFixtures.store(holding: .available, of: account)
        await store.refresh(account, on: .devnet)
        return (PrivateBalanceModel(store: store, network: .devnet), account)
    }

    /// Making SOL private opens a deposit of the account's public SOL.
    @Test func `Making SOL private opens a deposit of the public SOL`() async throws {
        let (model, account) = try await Self.model()
        let moveBalance = PrivateBalanceMoveAction(model: model, account: account, publicLamports: 2_000_000_000)

        moveBalance(.toPrivate)

        #expect(model.move?.direction == .toPrivate)
        #expect(model.move?.payment.token.balance == 2)
    }

    /// Making SOL public opens a withdrawal of the available private SOL.
    @Test func `Making SOL public opens a withdrawal of the available SOL`() async throws {
        let (model, account) = try await Self.model()
        let moveBalance = PrivateBalanceMoveAction(model: model, account: account, publicLamports: 2_000_000_000)

        moveBalance(.toPublic)

        #expect(model.move?.direction == .toPublic)
        #expect(model.move?.payment.token.balance == Decimal(string: "0.001"))
    }
}
