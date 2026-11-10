import SwiftUI

/// Runs a transaction review's steps and refreshes, signals how the transaction settled, and presents errors.
private struct TransactionReviewLifecycle<Proposal: TransactionProposal>: ViewModifier {
    @Bindable var review: TransactionReviewModel<Proposal>

    func body(content: Content) -> some View {
        let attempt = review.attempt
        content
            .task(id: attempt) { await review.run(attempt) }
            .task {
                while (try? await Task.sleep(for: review.proposal.refreshInterval)) != nil {
                    await review.refreshReview()
                }
            }
            .sensoryFeedback(trigger: review.outcome) { _, outcome in
                switch outcome {
                case .succeeded?: .success
                case .failed?, .dropped?: .error
                case nil: nil
                }
            }
            .alert(error: $review.error, retry: review.retry)
    }
}

extension View {
    /// Runs a transaction review's steps and refreshes while this view shows.
    ///
    /// - Parameter review: The review to run.
    /// - Returns: The view with the review's tasks, haptics, and alerts.
    func transactionReviewLifecycle<Proposal: TransactionProposal>(of review: TransactionReviewModel<Proposal>)
        -> some View {
        modifier(TransactionReviewLifecycle(review: review))
    }
}
