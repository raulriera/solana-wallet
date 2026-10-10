/// A scan cannot be completed with the supplied range or provider response.
nonisolated enum AccountDiscoveryError: Error, Equatable {
    case invalidRange
    case mismatchedAccounts
}
