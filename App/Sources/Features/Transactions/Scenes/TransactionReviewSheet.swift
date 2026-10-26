import SwiftUI

/// Presents a transaction's review, as tall as its content, and replaces it with the result once the transaction
/// settles.
///
/// Cancel closes the review, even while the transaction is sent: the shared transactions keep sending and watching it.
/// While it waits to settle, the review shows that it's sending, also after a watch stopped; a later watch settles it.
/// The result can't be swiped away; Close closes it.
struct TransactionReviewSheet<ReviewScreen: TransactionReviewContent, ResultScreen: TransactionResultContent>: View
    where ResultScreen.Proposal == ReviewScreen.Proposal {
    @Environment(\.dismiss) private var dismiss
    let review: TransactionReviewModel<ReviewScreen.Proposal>
    /// The outcome that shows, which follows the transaction's in an animated change.
    @State private var shownOutcome: TransactionOutcome?

    var body: some View {
        NavigationStack {
            Group {
                // The review and its result hold little, so the sheet is as tall as each; each measures itself, so
                // the sheet resizes when the result replaces the review.
                if let outcome = shownOutcome {
                    ResultScreen(review: review, outcome: outcome)
                        .contentHeightDetent()
                        .closeAction { dismiss() }
                } else {
                    ReviewScreen(review: review)
                        .contentHeightDetent()
                        .cancellationAction()
                }
            }
            // The result blurs in over the review.
            .transition(.blurReplace)
        }
        .limitedTextSize()
        // `animation(_:value:)` doesn't animate this swap, so the change itself is animated.
        .onChange(of: review.outcome, initial: true) { _, outcome in
            withAnimation { shownOutcome = outcome }
        }
        // A settled transaction stays until the person reads how it settled.
        .interactiveDismissDisabled(review.outcome != nil)
    }
}
