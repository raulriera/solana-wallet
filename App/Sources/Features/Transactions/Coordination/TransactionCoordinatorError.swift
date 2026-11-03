/// An error that stops a transaction coordinator's work.
nonisolated enum TransactionCoordinatorError: Error, Sendable, Equatable {
    /// The review already started signing.
    case reviewAlreadyUsed
    /// The submission strategy has no route on the provider's network.
    case unsupportedNetwork
}
