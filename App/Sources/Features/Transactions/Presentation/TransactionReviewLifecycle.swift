import SwiftUI

/// Runs a transaction's review steps while its sheet shows, simulates the review again before it expires, signals how
/// the transaction settled, and presents errors.
private struct TransactionReviewLifecycle<Proposal: TransactionProposal>: ViewModifier {
    @Bindable var review: TransactionReviewModel<Proposal>

    /// Attaches the review's tasks, haptics, and alerts.
    /// - Parameter content: The review's sheet.
    /// - Returns: The sheet with managed steps, refreshes, outcome haptics, and error presentation.
    func body(content: Content) -> some View {
        let attempt = review.attempt
        content
            .task(id: attempt) { await review.run(attempt) }
            // The model skips refreshes while a step runs and after the transaction is sent.
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
            // Alerts show from the topmost presentation, so errors while the review shows appear over it.
            .errorAlert($review.error, retry: review.retry)
    }
}

extension TransactionReviewSheet {
    /// Runs the review's steps and refreshes only while the sheet shows.
    /// - Returns: The sheet with managed steps, refreshes, outcome haptics, and error presentation.
    func transactionReviewLifecycle() -> some View {
        modifier(TransactionReviewLifecycle(review: review))
    }
}
