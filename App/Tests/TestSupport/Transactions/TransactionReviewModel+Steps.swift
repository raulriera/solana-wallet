import Testing
import Transactions
@testable import widgets

extension TransactionReviewModel {
    /// Prepares and simulates the review, as its sheet does when it opens.
    /// - Throws: A test failure when the review can't be approved.
    func runReview() async throws {
        prepareReview()
        await run(attempt)
        try #require(canApprove)
    }

    /// Approves the reviewed transaction and sends it.
    /// - Returns: The sent transaction's record.
    /// - Throws: A test failure when nothing was sent.
    func runApproval() async throws -> TransactionRecord {
        approve()
        await run(attempt)
        return try #require(record)
    }
}
