import Observation
import SwiftUI
@testable import widgets

/// Keeps the latest payment's review, as the contacts tab does.
@MainActor
@Observable
final class KeptPaymentReview {
    /// The latest payment's review, which stays after it closes.
    var review: TransactionReviewModel<PaymentProposal>?
}

/// Clears a keypad's amount once its sent payment succeeds, as the contacts tab does.
struct SentAmountClearingRoot: View {
    /// The keypad's payment.
    let payment: PaymentModel
    /// The latest review.
    let kept: KeptPaymentReview

    var body: some View {
        @Bindable var kept = kept
        Color.clear
            .clearsSentAmount(payment, review: $kept.review)
    }
}
