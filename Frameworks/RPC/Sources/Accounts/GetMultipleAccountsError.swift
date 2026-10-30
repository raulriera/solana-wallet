/// An error for an invalid account read request.
public enum GetMultipleAccountsError: Error, Sendable, Equatable {
    /// The request doesn't have one to 100 addresses.
    case invalidAddressCount
}
