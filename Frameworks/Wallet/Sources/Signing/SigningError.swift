/// An error from signing a message.
public enum SigningError: Error, Sendable, Equatable {
    /// The recovered account isn't the expected signer.
    case signerMismatch
    /// The message is a Solana Rings key derivation input.
    case reservedMessage
}
