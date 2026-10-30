/// An error that a transaction review presents, with the cases that every review shares.
nonisolated protocol TransactionReviewError: RetryableError, Equatable {
    /// The transaction couldn't be prepared or simulated.
    static var preparationFailed: Self { get }
    /// The transaction couldn't be signed or sent.
    static var notSent: Self { get }
}
