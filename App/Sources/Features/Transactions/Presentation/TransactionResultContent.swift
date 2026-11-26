import SwiftUI

/// A screen that shows a sent transaction's outcome.
protocol TransactionResultContent: View {
    /// The kind of transaction whose result the screen shows.
    associatedtype Proposal: TransactionProposal

    /// Creates the screen for a sent transaction.
    ///
    /// - Parameters:
    ///   - review: The transaction's review.
    ///   - outcome: The transaction's outcome.
    init(review: TransactionReviewModel<Proposal>, outcome: TransactionOutcome)
}
