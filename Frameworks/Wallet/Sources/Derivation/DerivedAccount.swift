/// A public address and the hardened path that derives it.
public struct DerivedAccount: Sendable, Equatable {
    /// The Base58-encoded Ed25519 public key.
    public let address: String
    public let path: DerivationPath

    /// Creates a derived account.
    ///
    /// - Parameters:
    ///   - address: The derived public address.
    ///   - path: The path that derives the address.
    public init(address: String, path: DerivationPath) {
        self.address = address
        self.path = path
    }
}
