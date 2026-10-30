/// An error that stops an account from being saved.
nonisolated enum AccountStoreError: Error {
    /// An account with the same identifier, address, or recovery and path is saved.
    case duplicateAccount
}
