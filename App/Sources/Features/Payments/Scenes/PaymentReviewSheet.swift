import SwiftUI

/// Presents a payment's review in its own navigation container.
struct PaymentReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let payment: PaymentModel
    let recipient: PaymentRecipient
    /// The person's own history, which the review's checks compare the recipient with.
    let context: RecipientContext

    var body: some View {
        NavigationStack {
            PaymentReviewScreen(payment: payment, recipient: recipient,
                                warnings: RecipientClassifier.review.warnings(for: recipient.address, in: context))
                // The review holds little, so the sheet is as tall as its content.
                .contentHeightDetent()
                .cancellationAction()
                .confirmationAction("Send", isEnabled: payment.canSend) { dismiss() }
        }
    }
}
