import SwiftUI

/// Presents a payment's review in its own navigation container.
struct PaymentReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let payment: PaymentModel

    var body: some View {
        NavigationStack {
            PaymentReviewScreen(payment: payment)
                // The review holds little, so the sheet is as tall as its content.
                .contentHeightDetent()
                .cancellationAction()
                .confirmationAction("Send", isEnabled: payment.canSend) { dismiss() }
        }
    }
}
