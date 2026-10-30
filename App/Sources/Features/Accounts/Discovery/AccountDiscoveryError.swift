/// An error that stops the discovery of a phrase's accounts.
nonisolated enum AccountDiscoveryError: Error, Equatable {
    case mismatchedAccounts
}
