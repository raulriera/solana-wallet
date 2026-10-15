/// A private-balance key failure that contains no recovery material or rejected input.
public enum PrivateBalanceError: Error, Sendable, Equatable {
    /// The path isn't a Solana account path `m/44'/501'/i'/0'`, the only family with private-balance keys.
    case unsupportedPath
    /// The phrase, passphrase, and path don't derive the account at the expected address.
    case accountMismatch
}
