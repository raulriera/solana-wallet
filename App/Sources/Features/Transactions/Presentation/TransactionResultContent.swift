import SwiftUI

/// A screen that shows how a sent transaction settled, such as a payment that reached its recipient.
protocol TransactionResultContent: View {
    /// The kind of transaction whose result the screen shows.
    associatedtype Proposal: TransactionProposal

    /// Creates the screen for a settled transaction.
    /// - Parameters:
    ///   - review: The transaction's review, which keeps its record.
    ///   - outcome: How the transaction settled.
    init(review: TransactionReviewModel<Proposal>, outcome: TransactionOutcome)
}
