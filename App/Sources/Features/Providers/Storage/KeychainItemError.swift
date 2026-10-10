/// A Keychain storage error that never contains the stored value.
nonisolated enum KeychainItemError: Error, Equatable {
    /// The stored bytes don't represent a value of the item's type.
    case unreadable
    /// A Security framework failure, identified only by its status code.
    case keychain(status: Int32)
}
