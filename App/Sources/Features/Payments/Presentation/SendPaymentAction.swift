import SwiftUI

/// Opens the review of the typed payment from the keypad's Send button, the way SwiftUI's `dismiss` acts for the view
/// that reads it.
struct SendPaymentAction {
    /// The window's account, network, and transactions.
    let sender: PaymentSender
    /// The keypad's payment.
    let payment: PaymentModel
    /// Who the payment goes to.
    let recipient: PaymentRecipient
    /// The person's own history, which the review's checks compare the recipient with.
    let context: RecipientContext
    /// The latest payment's review, which stays after it closes.
    let review: Binding<TransactionReviewModel<PaymentProposal>?>
    /// The review that shows, or `nil` while none does.
    let presented: Binding<TransactionReviewModel<PaymentProposal>?>
    /// Why a payment couldn't start.
    let error: Binding<SendError?>

    /// Opens a review of the typed amount and starts simulating it; nothing opens while the amount can't be sent or a
    /// review shows.
    func callAsFunction() {
        guard presented.wrappedValue == nil, payment.canSend else { return }
        do {
            let model = try sender.review(payment.amount, to: recipient, in: context)
            model.prepareReview()
            review.wrappedValue = model
            presented.wrappedValue = model
        } catch {
            self.error.wrappedValue = .preparationFailed
        }
    }
}
