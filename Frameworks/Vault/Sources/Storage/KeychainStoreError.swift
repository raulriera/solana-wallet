/// A storage failure that contains no recovery material or underlying error text.
public enum KeychainStoreError: Error, Sendable, Equatable {
    /// The recovery identifier already has stored recovery material.
    case duplicateRecovery
    /// No item exists, including items the system deleted when the device passcode was removed.
    case recoveryUnavailable
    /// Authentication didn't authorize access to the item.
    case authenticationFailed
    /// Keychain access couldn't present authentication in the current state.
    case interactionNotAllowed
    /// The device has no passcode, or the requested item protection is unavailable.
    case protectionUnavailable
    /// The stored recovery payload is malformed or has an unsupported version.
    case invalidRecovery
    /// Another Security framework failure, identified only by its status code.
    case keychain(status: Int32)
}
