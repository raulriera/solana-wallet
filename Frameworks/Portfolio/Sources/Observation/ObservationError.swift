/// An error from observing finalized wallet changes.
public enum ObservationError: Error, Sendable, Equatable {
    /// No account-change provider is configured.
    case providerUnavailable
}
