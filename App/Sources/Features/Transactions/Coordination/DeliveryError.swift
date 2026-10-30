/// An error from sending or confirming a transaction, with the transaction's receipt.
nonisolated struct DeliveryError: Error, Sendable {
    let submission: Submission
    let cause: any Error

    /// Creates a delivery error.
    ///
    /// - Parameters:
    ///   - submission: The transaction's receipt.
    ///   - cause: The error that stopped sending or confirming.
    init(submission: Submission, cause: any Error) {
        self.submission = submission
        self.cause = cause
    }
}
