/// A failed delivery or observation with the receipt needed to reconcile its outcome.
nonisolated struct DeliveryError: Error, Sendable {
    /// The locally verified signature, network, and blockhash expiry, even when acknowledgment was lost.
    let submission: Submission
    /// The original error, including rate-limit details or cancellation.
    let cause: any Error

    /// Retains delivery context without asserting whether the transaction reached a validator.
    /// - Parameters:
    ///   - submission: The signed transaction's receipt, including its blockhash expiry.
    ///   - cause: The unchanged delivery or observation error.
    init(submission: Submission, cause: any Error) {
        self.submission = submission
        self.cause = cause
    }
}
