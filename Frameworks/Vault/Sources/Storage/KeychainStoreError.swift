/// An error from the recovery Keychain store.
public enum KeychainStoreError: Error, Sendable, Equatable {
    /// Recovery material is already stored for the identifier.
    case duplicateRecovery
    /// No recovery material is stored for the identifier.
    case recoveryUnavailable
    case authenticationFailed
    /// Authentication couldn't be presented or didn't finish in time.
    case interactionNotAllowed
    /// The device has no passcode or can't protect the item.
    case protectionUnavailable
    /// The stored recovery payload is malformed or unsupported.
    case invalidRecovery
    /// Another Security framework error.
    case keychain(status: Int32)
}
