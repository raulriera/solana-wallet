/// An account that can't be saved.
nonisolated enum AccountStoreError: Error {
    /// An account ID, public address, or recovery-and-path pair occurs more than once.
    case duplicateAccount
}
