import SwiftUI

/// Presents a payment's review over its keypad, as tall as its content, and replaces it with the result once the
/// payment is sent.
///
/// Cancel returns to the keypad with the amount as typed, except while the payment is sent; the result can't be
/// swiped away, and Close closes it.
struct PaymentReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let send: SendModel
    /// The person's own history, which the review's checks compare the recipient with.
    let context: RecipientContext
    /// The outcome that shows, which follows the payment's in an animated change.
    @State private var shownOutcome: SendModel.Outcome?

    var body: some View {
        NavigationStack {
            Group {
                // The review and its result hold little, so the sheet is as tall as each; each measures itself, so
                // the sheet resizes when the result replaces the review.
                if let outcome = shownOutcome {
                    PaymentResultScreen(send: send, outcome: outcome)
                        .contentHeightDetent()
                        .closeAction { dismiss() }
                } else {
                    PaymentReviewScreen(send: send, warnings: RecipientClassifier.review.warnings(
                        for: send.recipient.address, in: context
                    ))
                    .contentHeightDetent()
                    .cancellationAction()
                    .disabled(send.isSending)
                }
            }
            // The result blurs in over the review.
            .transition(.blurReplace)
        }
        .limitedTextSize()
        // `animation(_:value:)` doesn't animate this swap, so the change itself is animated.
        .onChange(of: send.outcome, initial: true) { _, outcome in
            withAnimation { shownOutcome = outcome }
        }
        // A sent payment stays until the person reads how it settled.
        .interactiveDismissDisabled(send.isSending || send.submission != nil)
    }
}
