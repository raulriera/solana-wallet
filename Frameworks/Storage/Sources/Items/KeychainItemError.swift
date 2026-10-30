/// An error from a Keychain item.
public enum KeychainItemError: Error, Equatable {
    /// The stored bytes don't decode to a value.
    case unreadable
    /// The value's bytes don't decode back to an equal value.
    case unencodable
    /// A Security framework error.
    case keychain(status: Int32)
}
