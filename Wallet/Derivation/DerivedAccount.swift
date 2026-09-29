/// A public address paired with the exact hardened path needed to recover it.
public struct DerivedAccount: Sendable, Equatable {
    /// The Base58-encoded Ed25519 public key.
    public let address: String
    /// The derivation path relative to the supplied recovery phrase and passphrase.
    public let path: DerivationPath

    /// Creates a derived account without retaining recovery material.
    /// - Parameters:
    ///   - address: The derived public address.
    ///   - path: The path used to derive the address.
    public init(address: String, path: DerivationPath) {
        self.address = address
        self.path = path
    }
}
