import SwiftUI

/// Clears the keypad's amount once the payment sent with it succeeds, and forgets that payment once the person types
/// another amount, so only this modifier reads each key press.
///
/// The review keeps the sent payment's record, and the shared transactions keep watching it after the review closes,
/// so the amount clears whenever the payment lands, even after the person cancelled its review, and when the tab shows
/// again after it landed. The review is forgotten once the amount clears, so the amount clears only once; a review
/// that shows keeps its own reference.
private struct SentAmountClearing: ViewModifier {
    /// The keypad's payment, or `nil` while there's nothing to pay with.
    let payment: PaymentModel?
    /// The latest payment's review, which stays after it closes until the amount clears or changes.
    @Binding var review: TransactionReviewModel<PaymentProposal>?

    /// Attaches the changes that clear the amount and forget the sent payment.
    /// - Parameter content: The view that owns the amount.
    /// - Returns: The view, which clears the amount once the sent payment succeeds.
    func body(content: Content) -> some View {
        content
            .onChange(of: review?.status, initial: true) { _, status in
                guard status == .succeeded, let payment else { return }
                withAnimation { payment.clear() }
                review = nil
            }
            // A newly typed amount isn't the one that was sent, so a later success leaves it as typed.
            .onChange(of: payment?.pressCount) {
                review = nil
            }
    }
}

extension View {
    /// Clears the keypad's amount once the payment sent with it succeeds, until the person types another amount.
    /// - Parameters:
    ///   - payment: The keypad's payment, or `nil` while there's nothing to pay with.
    ///   - review: The latest payment's review, which stays after it closes; clearing the amount or a key press
    ///     forgets it.
    /// - Returns: A view that clears the amount once the sent payment succeeds.
    func clearsSentAmount(_ payment: PaymentModel?, review: Binding<TransactionReviewModel<PaymentProposal>?>)
        -> some View {
        modifier(SentAmountClearing(payment: payment, review: review))
    }
}
