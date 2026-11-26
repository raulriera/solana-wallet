import SwiftUI

/// Runs a transaction review's steps and refreshes, signals how the transaction settled, presents errors, and stops
/// a send with several transactions when the app goes to the background.
private struct TransactionReviewLifecycle<Proposal: TransactionProposal>: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
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
                switch outcome?.status {
                case .succeeded?: .success
                case .failed?, .dropped?: .error
                case .pending?, nil: nil
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { review.stopSending() }
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
