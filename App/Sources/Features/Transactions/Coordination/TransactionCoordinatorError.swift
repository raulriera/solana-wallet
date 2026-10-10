/// A review cannot authorize more than one signing attempt.
nonisolated enum TransactionCoordinatorError: Error, Sendable, Equatable {
    /// This review has already entered signing, including an attempt that later failed.
    case reviewAlreadyUsed
}
