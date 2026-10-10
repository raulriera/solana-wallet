/// A storage failure that never contains the key.
nonisolated enum ProviderKeyStoreError: Error, Equatable {
    /// The stored value isn't valid UTF-8 text.
    case unreadable
    /// A Security framework failure, identified only by its status code.
    case keychain(status: Int32)
}
