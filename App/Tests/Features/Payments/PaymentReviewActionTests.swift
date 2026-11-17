import RPC
import SwiftUI
import Testing
import Transactions
@testable import widgets

@MainActor
struct PaymentReviewActionTests {
    @MainActor
    private final class Presented {
        var review: TransactionReviewModel<PaymentProposal>?
        var presented: TransactionReviewModel<PaymentProposal>?
        var error: SendError?
    }

    @Test func `Reviewing opens the review and starts simulating it`() throws {
        let presented = Presented()
        let payment = PaymentModel(tokens: [PaymentFixtures.sol], currencyCode: "USD")
        payment.press(.digit(1))

        try Self.action(payment: payment, presented: presented)()

        let review = try #require(presented.review)
        #expect(presented.presented === review)
        #expect(review.attempt?.work == .review)
        #expect(Decimal(review.proposal.sent) == 1)
        #expect(presented.error == nil)
    }

    @Test(arguments: [false, true])
    func `The review checks the recipient against the person's history`(paid: Bool) throws {
        let presented = Presented()
        let payment = PaymentModel(tokens: [PaymentFixtures.sol], currencyCode: "USD")
        payment.press(.digit(1))
        let recipient = try SigningFixture().transfer.accounts[1].address
        let context = RecipientContext(knownAddresses: paid ? [recipient] : [], paidAddresses: paid ? [recipient] : [])

        try Self.action(payment: payment, presented: presented, context: context)()

        #expect(try #require(presented.review).proposal.warnings == (paid ? [] : [.firstPayment]))
    }

    @Test func `Sending again replaces only a closed review`() throws {
        let presented = Presented()
        let payment = PaymentModel(tokens: [PaymentFixtures.sol], currencyCode: "USD")
        payment.press(.digit(1))
        let action = try Self.action(payment: payment, presented: presented)
        action()
        let first = try #require(presented.review)

        action()
        #expect(presented.review === first)

        presented.presented = nil
        action()

        #expect(presented.review !== first)
        #expect(presented.presented === presented.review)
    }

    @Test func `An empty amount opens nothing`() throws {
        let presented = Presented()

        try Self.action(payment: PaymentModel(tokens: [PaymentFixtures.sol], currencyCode: "USD"), presented: presented)()

        #expect(presented.review == nil)
        #expect(presented.presented == nil)
    }

    @Test func `Unavailable transactions explain the failure`() throws {
        let presented = Presented()
        let payment = PaymentModel(tokens: [PaymentFixtures.sol], currencyCode: "USD")
        payment.press(.digit(1))

        try Self.action(payment: payment, presented: presented,
                        transactions: .inMemory { _ in throw TransactionCoordinatorError.unsupportedNetwork })()

        #expect(presented.review == nil)
        #expect(presented.presented == nil)
        #expect(presented.error == .preparationFailed)
    }

    private static func action(payment: PaymentModel, presented: Presented,
                               context: RecipientContext = RecipientContext(knownAddresses: [], paidAddresses: []),
                               transactions: TransactionStore? = nil) throws -> PaymentReviewAction {
        let fixture = try SigningFixture()
        let preparation = try HTTPResponses.preparation(fixture: fixture.preparation)
        let local = TransactionStore.inMemory { _ in
            try TransactionCoordinator(rpc: preparation.client, store: SigningRecoveryStore(recovery: fixture.recovery))
        }
        let sender = PaymentSender(account: fixture.account, network: .devnet, transactions: transactions ?? local)
        return PaymentReviewAction(sender: sender, payment: payment,
                                 recipient: PaymentRecipient(address: fixture.transfer.accounts[1].address, name: nil),
                                 context: context,
                                 review: Binding { presented.review } set: { presented.review = $0 },
                                 presented: Binding { presented.presented } set: { presented.presented = $0 },
                                 error: Binding { presented.error } set: { presented.error = $0 })
    }
}
