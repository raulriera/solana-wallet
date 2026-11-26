import SwiftUI

/// Runs and shows a transaction's review and replaces it with the result once the transaction is sent, keeping the
/// person on the screen from the moment the send starts.
struct TransactionReviewScreen<ReviewScreen: TransactionReviewContent, ResultScreen: TransactionResultContent>: View
    where ResultScreen.Proposal == ReviewScreen.Proposal {
    let review: TransactionReviewModel<ReviewScreen.Proposal>
    /// The outcome on screen, which follows the review's outcome with an animation.
    @State private var shownOutcome: TransactionOutcome?

    var body: some View {
        ZStack {
            if let outcome = shownOutcome {
                ResultScreen(review: review, outcome: outcome)
                    .transition(.opacity)
            } else {
                ReviewScreen(review: review)
                    .transition(.opacity)
            }
        }
        .navigationBarBackButtonHidden(review.isSent)
        .interactiveDismissDisabled(review.isSent)
        .transactionReviewLifecycle(of: review)
        .onChange(of: review.outcome?.status, initial: true) {
            withAnimation { shownOutcome = review.outcome }
        }
    }
}
