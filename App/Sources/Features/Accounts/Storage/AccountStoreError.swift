/// A storage location or account identity that cannot be accepted.
nonisolated enum AccountStoreError: Error {
    /// Storage isn't a local regular file or its configured directory isn't local.
    case invalidStorage
    /// An account ID, public address, or recovery-and-path pair occurs more than once.
    case duplicateAccount
}
