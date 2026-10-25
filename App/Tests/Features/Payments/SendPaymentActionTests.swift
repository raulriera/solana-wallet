import RPC
import SwiftUI
import Testing
import Transactions
@testable import widgets

/// Checks that the keypad's Send button opens the payment's review and starts simulating it.
@MainActor
struct SendPaymentActionTests {
    /// The account's SOL, without a price.
    private static let sol = PaymentToken(mint: nil, symbol: "SOL", balance: 2, price: nil, decimals: 9)

    /// Holds what the action opens, as the keypad's stack does.
    @MainActor
    private final class Presented {
        var send: SendModel?
        var error: SendError?
    }

    /// Sending an amount that can be sent opens its review and starts simulating it.
    /// - Throws: A fixture error.
    @Test func `Sending opens the review and starts simulating it`() throws {
        let presented = Presented()
        let payment = PaymentModel(tokens: [Self.sol], currencyCode: "USD")
        payment.press(.digit(1))

        try Self.action(payment: payment, presented: presented)()

        let send = try #require(presented.send)
        #expect(send.attempt?.work == .review)
        #expect(send.amount.quantity == 1)
        #expect(presented.error == nil)
    }

    /// An empty amount opens nothing.
    /// - Throws: A fixture error.
    @Test func `An empty amount opens nothing`() throws {
        let presented = Presented()

        try Self.action(payment: PaymentModel(tokens: [Self.sol], currencyCode: "USD"), presented: presented)()

        #expect(presented.send == nil)
    }

    /// A network whose transactions can't be created explains it instead of opening a review.
    /// - Throws: A fixture error.
    @Test func `Unavailable transactions explain the failure`() throws {
        let presented = Presented()
        let payment = PaymentModel(tokens: [Self.sol], currencyCode: "USD")
        payment.press(.digit(1))

        try Self.action(payment: payment, presented: presented,
                        transactions: NetworkTransactions { _ in throw SubmitterError.noProviders })()

        #expect(presented.send == nil)
        #expect(presented.error == .preparationFailed)
    }

    /// Creates the action for a payment to a fixed recipient from a fixture account on devnet.
    /// - Parameters:
    ///   - payment: The keypad's payment.
    ///   - presented: Receives what the action opens.
    ///   - transactions: Every network's transaction coordinator, or `nil` for one that answers from local responses.
    /// - Returns: The action.
    /// - Throws: A fixture error.
    private static func action(payment: PaymentModel, presented: Presented,
                               transactions: NetworkTransactions? = nil) throws -> SendPaymentAction {
        let fixture = try SigningFixture()
        let preparation = try HTTPResponses.preparation(fixture: fixture.preparation)
        let local = NetworkTransactions { _ in
            try TransactionCoordinator(rpc: preparation.client, store: SigningRecoveryStore(recovery: fixture.recovery))
        }
        let sender = PaymentSender(account: fixture.account, network: .devnet, transactions: transactions ?? local,
                                   portfolio: RecordingPortfolio())
        return SendPaymentAction(sender: sender, payment: payment,
                                 recipient: PaymentRecipient(address: fixture.transfer.accounts[1].address, name: nil),
                                 send: Binding { presented.send } set: { presented.send = $0 },
                                 error: Binding { presented.error } set: { presented.error = $0 })
    }
}
