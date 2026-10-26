import SwiftUI

/// A screen that shows a proposed transaction's review before the person approves it from the top bar, such as a
/// payment's amount, recipient, and fees.
protocol TransactionReviewContent: View {
    /// The kind of transaction that the screen reviews.
    associatedtype Proposal: TransactionProposal

    /// Creates the screen for a review.
    /// - Parameter review: The review that the screen shows and approves.
    init(review: TransactionReviewModel<Proposal>)
}
