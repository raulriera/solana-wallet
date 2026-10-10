/// A key storage error that never contains the stored value.
nonisolated enum KeyStoreError: Error, Equatable {
    /// The stored value isn't in the format its store expects.
    case unreadable
    /// A Security framework failure, identified only by its status code.
    case keychain(status: Int32)
}
