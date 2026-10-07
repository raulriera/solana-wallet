/// A failure to observe or reconcile confirmed wallet changes.
public enum ObservationError: Error, Sendable, Equatable {
    /// No account-change provider is configured for this portfolio.
    case providerUnavailable
    /// The account-change provider observes a different network from the holdings source.
    case networkMismatch
}
