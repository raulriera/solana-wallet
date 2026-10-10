/// A local request error detected before networking.
public enum GetMultipleAccountsError: Error, Sendable, Equatable {
    /// A request must contain between one and 100 addresses.
    case invalidAddressCount
}
