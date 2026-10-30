extension DerivationPath {
    /// The coin type of Solana Rings keys.
    static let privateBalanceCoinType: UInt32 = 1_392_955_331

    /// Whether the path is a Solana account path `m/44'/501'/i'/0'`, the only kind with private-balance keys.
    public var hasPrivateBalanceKeys: Bool { privateBalanceAccount != nil }

    /// The account index i of a Solana account path `m/44'/501'/i'/0'`, or `nil` for any other path.
    var privateBalanceAccount: UInt32? {
        indices.count == 4 ? accountIndex : nil
    }

    /// Returns the Ed25519 path of an account's nullifier secret.
    ///
    /// - Parameter account: The account index i, below 2³¹.
    /// - Returns: The path `m/44'/1392955331'/i'/1'/0'`.
    static func nullifierSecret(account: UInt32) -> Self {
        Self(indices: [44, privateBalanceCoinType, account, 1, 0])
    }

    /// Returns the P-256 path of an account's viewing key.
    ///
    /// - Parameter account: The account index i, below 2³¹.
    /// - Returns: The path `m/44'/1392955331'/i'/2'/0'`.
    static func viewingKey(account: UInt32) -> Self {
        Self(indices: [44, privateBalanceCoinType, account, 2, 0])
    }

    /// Returns the Ed25519 path of an account's code root.
    ///
    /// - Parameter account: The account index i, below 2³¹.
    /// - Returns: The path `m/44'/1392955331'/i'/3'`.
    static func codeRoot(account: UInt32) -> Self {
        Self(indices: [44, privateBalanceCoinType, account, 3])
    }
}
