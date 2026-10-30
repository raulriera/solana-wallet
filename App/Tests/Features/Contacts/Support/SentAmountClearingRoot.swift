import Observation
import SwiftUI
@testable import widgets

@MainActor
@Observable
final class KeptPaymentReview {
    var review: TransactionReviewModel<PaymentProposal>?
}

struct SentAmountClearingRoot: View {
    let payment: PaymentModel
    let kept: KeptPaymentReview

    var body: some View {
        @Bindable var kept = kept
        Color.clear
            .clearsSentAmount(payment, review: $kept.review)
    }
}
