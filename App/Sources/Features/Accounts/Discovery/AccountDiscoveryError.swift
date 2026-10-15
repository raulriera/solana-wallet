/// A scan cannot be completed with the provider's response.
nonisolated enum AccountDiscoveryError: Error, Equatable {
    case mismatchedAccounts
}
