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
            .errorAlert($review.error, retry: review.retry)
    }
}

extension TransactionReviewSheet {
    /// Runs the review's steps and refreshes while the sheet shows.
    ///
    /// - Returns: The sheet with the review's tasks, haptics, and alerts.
    func transactionReviewLifecycle() -> some View {
        modifier(TransactionReviewLifecycle(review: review))
    }
}
