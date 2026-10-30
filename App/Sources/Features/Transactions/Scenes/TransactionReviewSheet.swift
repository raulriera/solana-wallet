import SwiftUI

/// Presents a transaction's review and replaces it with the result once the transaction settles.
struct TransactionReviewSheet<ReviewScreen: TransactionReviewContent, ResultScreen: TransactionResultContent>: View
    where ResultScreen.Proposal == ReviewScreen.Proposal {
    @Environment(\.dismiss) private var dismiss
    let review: TransactionReviewModel<ReviewScreen.Proposal>
    /// The outcome on screen, which follows the review's outcome with an animation.
    @State private var shownOutcome: TransactionOutcome?

    var body: some View {
        NavigationStack {
            Group {
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
            .transition(.blurReplace)
        }
        .limitedTextSize()
        .onChange(of: review.outcome, initial: true) { _, outcome in
            withAnimation { shownOutcome = outcome }
        }
        .interactiveDismissDisabled(review.outcome != nil)
    }
}
