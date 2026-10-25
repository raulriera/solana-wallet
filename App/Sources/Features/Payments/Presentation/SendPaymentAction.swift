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
    /// The payment whose review shows.
    let send: Binding<SendModel?>
    /// Why a payment couldn't start.
    let error: Binding<SendError?>

    /// Opens the review and starts simulating it; nothing opens while the amount can't be sent or a review shows.
    func callAsFunction() {
        guard send.wrappedValue == nil, payment.canSend else { return }
        do {
            let model = try sender.send(payment, to: recipient, in: context)
            model.prepareReview()
            send.wrappedValue = model
        } catch {
            self.error.wrappedValue = .preparationFailed
        }
    }
}
