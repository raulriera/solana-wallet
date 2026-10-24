import Foundation
import Testing
import Transactions
@testable import widgets

/// Checks that the private balance's move action opens a move in the direction it's asked for.
@MainActor
struct PrivateBalanceMoveActionTests {
    /// A private balance on, with 1,000,000 lamports available.
    /// - Returns: The window's private balance.
    /// - Throws: A fixture error.
    private static func model() async throws -> PrivateBalanceModel {
        let account = try await PrivateBalanceFixtures.account()
        let model = try PrivateBalanceModel.fixture(
            HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]),
            keys: StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        )
        await model.refresh(for: account)
        model.show(.balance(available: 1_000_000, pending: 0))
        return model
    }

    /// Making SOL private opens a deposit of the account's public SOL.
    @Test func `Making SOL private opens a deposit of the public SOL`() async throws {
        let model = try await Self.model()
        let moveBalance = PrivateBalanceMoveAction(model: model, publicLamports: 2_000_000_000)

        moveBalance(.toPrivate)

        #expect(model.move?.direction == .toPrivate)
        #expect(model.move?.payment.token.balance == 2)
    }

    /// Making SOL public opens a withdrawal of the available private SOL.
    @Test func `Making SOL public opens a withdrawal of the available SOL`() async throws {
        let model = try await Self.model()
        let moveBalance = PrivateBalanceMoveAction(model: model, publicLamports: 2_000_000_000)

        moveBalance(.toPublic)

        #expect(model.move?.direction == .toPublic)
        #expect(model.move?.payment.token.balance == Decimal(string: "0.001"))
    }
}
