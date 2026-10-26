/// An error that a transaction's review explains in an alert, with the cases that every review shares.
///
/// Each kind of transaction names its own errors, so its alerts speak about what it does, such as a payment.
nonisolated protocol TransactionReviewError: RetryableError, Equatable {
    /// The transaction couldn't be prepared or simulated, such as after a provider error.
    static var preparationFailed: Self { get }
    /// The transaction couldn't be signed or sent, so nothing left the wallet.
    static var notSent: Self { get }
}
