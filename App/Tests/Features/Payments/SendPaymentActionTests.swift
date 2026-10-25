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

    /// The review asks the person to check a recipient they haven't paid, and only then.
    /// - Parameter paid: Whether the person paid the recipient before.
    /// - Throws: A fixture error.
    @Test(arguments: [false, true])
    func `The review checks the recipient against the person's history`(paid: Bool) throws {
        let presented = Presented()
        let payment = PaymentModel(tokens: [Self.sol], currencyCode: "USD")
        payment.press(.digit(1))
        let recipient = try SigningFixture().transfer.accounts[1].address
        let context = RecipientContext(knownAddresses: paid ? [recipient] : [], paidAddresses: paid ? [recipient] : [])

        try Self.action(payment: payment, presented: presented, context: context)()

        #expect(try #require(presented.send).warnings == (paid ? [] : [.firstPayment]))
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
                        transactions: .inMemory { _ in throw SubmitterError.noProviders })()

        #expect(presented.send == nil)
        #expect(presented.error == .preparationFailed)
    }

    /// Creates the action for a payment to a fixed recipient from a fixture account on devnet.
    /// - Parameters:
    ///   - payment: The keypad's payment.
    ///   - presented: Receives what the action opens.
    ///   - context: The person's own history, which the review's checks compare the recipient with.
    ///   - transactions: The shared transactions, or `nil` for ones whose coordinator answers from local responses.
    /// - Returns: The action.
    /// - Throws: A fixture error.
    private static func action(payment: PaymentModel, presented: Presented,
                               context: RecipientContext = RecipientContext(knownAddresses: [], paidAddresses: []),
                               transactions: TransactionStore? = nil) throws -> SendPaymentAction {
        let fixture = try SigningFixture()
        let preparation = try HTTPResponses.preparation(fixture: fixture.preparation)
        let local = TransactionStore.inMemory { _ in
            try TransactionCoordinator(rpc: preparation.client, store: SigningRecoveryStore(recovery: fixture.recovery))
        }
        let sender = PaymentSender(account: fixture.account, network: .devnet, transactions: transactions ?? local)
        return SendPaymentAction(sender: sender, payment: payment,
                                 recipient: PaymentRecipient(address: fixture.transfer.accounts[1].address, name: nil),
                                 context: context,
                                 send: Binding { presented.send } set: { presented.send = $0 },
                                 error: Binding { presented.error } set: { presented.error = $0 })
    }
}
