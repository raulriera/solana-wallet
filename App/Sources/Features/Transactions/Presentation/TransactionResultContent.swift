import RPC
import SwiftUI

/// A screen that shows how a sent transaction settled.
protocol TransactionResultContent: View {
    /// The kind of transaction whose result the screen shows.
    associatedtype Proposal: TransactionProposal

    /// Creates the screen for a settled transaction.
    ///
    /// - Parameters:
    ///   - review: The transaction's review.
    ///   - outcome: How the transaction settled.
    init(review: TransactionReviewModel<Proposal>, outcome: TransactionOutcome)
}
