import Testing
@testable import widgets

/// Checks which outcome a sent transaction's record shows.
struct TransactionOutcomeTests {
    /// Each settled status shows its outcome, and a pending one shows none.
    /// - Parameters:
    ///   - status: The record's status.
    ///   - outcome: The outcome that the result shows.
    @Test(arguments: [
        (TransactionRecord.Status.pending, nil),
        (.succeeded, TransactionOutcome.succeeded),
        (.failed, .failed),
        (.dropped, .dropped),
    ])
    func `A settled status shows its outcome`(status: TransactionRecord.Status, outcome: TransactionOutcome?) {
        #expect(TransactionOutcome(status) == outcome)
    }
}
