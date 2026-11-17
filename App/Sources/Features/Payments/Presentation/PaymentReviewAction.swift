import SwiftUI

/// An action that opens the review of the typed payment.
struct PaymentReviewAction {
    let sender: PaymentSender
    let payment: PaymentModel
    let recipient: PaymentRecipient
    let context: RecipientContext
    /// The review of the last sent payment.
    let review: Binding<TransactionReviewModel<PaymentProposal>?>
    /// The review that shows, or `nil` when none does.
    let presented: Binding<TransactionReviewModel<PaymentProposal>?>
    let error: Binding<SendError?>

    /// Opens a review of the typed amount and starts simulating it.
    func callAsFunction() {
        guard presented.wrappedValue == nil, payment.canSend else { return }
        do {
            let model = try sender.review(payment, to: recipient, in: context)
            model.prepareReview()
            review.wrappedValue = model
            presented.wrappedValue = model
        } catch {
            self.error.wrappedValue = .preparationFailed
        }
    }
}
