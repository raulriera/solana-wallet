/// An error for a review that already started signing.
nonisolated enum TransactionCoordinatorError: Error, Sendable, Equatable {
    case reviewAlreadyUsed
}
