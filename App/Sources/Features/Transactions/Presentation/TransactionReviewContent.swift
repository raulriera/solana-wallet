import SwiftUI

/// A screen that shows a proposed transaction for the person to approve.
protocol TransactionReviewContent: View {
    /// The kind of transaction that the screen reviews.
    associatedtype Proposal: TransactionProposal

    /// Creates the screen for a review.
    ///
    /// - Parameter review: The review to show.
    init(review: TransactionReviewModel<Proposal>)
}
