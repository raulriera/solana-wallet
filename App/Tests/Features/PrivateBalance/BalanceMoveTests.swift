import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

/// Checks an open move's keypad amount and the review it starts.
@MainActor
struct BalanceMoveTests {
    /// Each direction types SOL from the balance that it leaves, up to that balance's spendable SOL.
    /// - Parameters:
    ///   - direction: Which balance the SOL leaves.
    ///   - source: The balance that the keypad names.
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

    /// A review takes the amount as typed when it starts, so later key presses never change it.
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

    /// A network without a transaction coordinator starts no review.
    @Test
    func `A review fails without a transaction coordinator`() async throws {
        let move = try await Self.move(.toPrivate, transactions: .inMemory { _ in throw SubmitterError.noProviders })

        #expect(throws: SubmitterError.noProviders) { try move.review() }
    }

    /// Creates a fixture account's move on devnet from a balance of 1.5 SOL.
    /// - Parameters:
    ///   - direction: Which balance the SOL leaves.
    ///   - transactions: The shared transactions, whose coordinator never leaves the process by default.
    /// - Returns: The move, with nothing typed.
    /// - Throws: A fixture error.
    private static func move(_ direction: BalanceMoveProposal.Direction,
                             transactions: TransactionStore = .unused) async throws -> BalanceMove {
        // Unplanned requests fail instead of reaching the network.
        let balances = PrivateBalances.inMemory(keys: StoredValue(), notes: StoredValue(),
                                                recovery: try PrivateBalanceFixtures.recoveryStore(),
                                                responses: HTTPResponses([:]))
        return BalanceMove(direction: direction, account: try await PrivateBalanceFixtures.account(), network: .devnet,
                           spendableLamports: 1_500_000_000, balances: balances, transactions: transactions)
    }
}
