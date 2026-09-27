/// A signing failure that contains no recovery material or rejected input.
public enum SigningError: Error, Sendable, Equatable {
    /// The phrase, passphrase, and path don't derive the intended signing account.
    case signerMismatch
}
