import SwiftUI

/// A modifier that clears the keypad's amount once the payment sent with it succeeds.
private struct SentAmountClearing: ViewModifier {
    /// The keypad's payment, or `nil` when there's nothing to pay with.
    let payment: PaymentModel?
    /// The review of the last sent payment, or `nil` once the amount clears or changes.
    @Binding var review: TransactionReviewModel<PaymentProposal>?

    func body(content: Content) -> some View {
        content
            .onChange(of: review?.status, initial: true) { _, status in
                guard status == .succeeded, let payment else { return }
                withAnimation { payment.clear() }
                review = nil
            }
            .onChange(of: payment?.pressCount) {
                review = nil
            }
    }
}

extension View {
    /// Clears the keypad's amount once the payment sent with it succeeds, until the person types another amount.
    ///
    /// - Parameters:
    ///   - payment: The keypad's payment, or `nil` when there's nothing to pay with.
    ///   - review: The review of the last sent payment.
    /// - Returns: A view that clears the amount once the sent payment succeeds.
    func clearsSentAmount(_ payment: PaymentModel?, review: Binding<TransactionReviewModel<PaymentProposal>?>)
        -> some View {
        modifier(SentAmountClearing(payment: payment, review: review))
    }
}
