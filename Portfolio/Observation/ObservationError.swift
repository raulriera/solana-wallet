/// A failure to observe or reconcile confirmed wallet changes.
public enum ObservationError: Error, Sendable, Equatable {
    /// No account-change provider is configured for this portfolio.
    case providerUnavailable
    /// The account-change provider observes a different network from the holdings source.
    case networkMismatch
    /// DAS hasn't reported indexing through the latest observed change, or omitted its watermark.
    case indexingBehind(expected: UInt64, observed: UInt64?)
}
