import SwiftUI

/// Presents a payment's review over its keypad, as tall as its content, and replaces it with the result once the
/// payment is sent.
///
/// Cancel returns to the keypad with the amount as typed, even while the payment is sent: the shared transactions keep
/// sending and watching it, and the keypad clears once it succeeds. The result can't be swiped away; Close closes it.
struct PaymentReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let send: SendModel
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
                    PaymentReviewScreen(send: send)
                        .contentHeightDetent()
                        .cancellationAction()
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
        // A settled payment stays until the person reads how it settled.
        .interactiveDismissDisabled(send.outcome != nil)
    }
}
