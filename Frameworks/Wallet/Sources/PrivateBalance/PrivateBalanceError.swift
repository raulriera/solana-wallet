/// An error from deriving private-balance keys.
public enum PrivateBalanceError: Error, Sendable, Equatable {
    /// The path isn't a Solana account path `m/44'/501'/i'/0'`.
    case unsupportedPath
    /// The recovered account isn't at the expected address.
    case accountMismatch
}
