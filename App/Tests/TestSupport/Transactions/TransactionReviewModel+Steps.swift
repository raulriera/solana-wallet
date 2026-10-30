import Testing
import Transactions
@testable import widgets

extension TransactionReviewModel {
    func runReview() async throws {
        prepareReview()
        await run(attempt)
        try #require(canApprove)
    }

    func runApproval() async throws -> TransactionRecord {
        approve()
        await run(attempt)
        return try #require(record)
    }
}
