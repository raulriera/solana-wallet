import Testing
@testable import widgets

struct TransactionOutcomeTests {
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
