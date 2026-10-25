extension DerivationPath {
    /// The coin type of Solana Rings keys.
    ///
    /// It's the first four bytes of SHA-256(`luminous.TSPP.v1`) as a big-endian integer, without
    /// its top bit.
    static let privateBalanceCoinType: UInt32 = 1_392_955_331

    /// Whether the path has private-balance keys: only Solana account paths `m/44'/501'/i'/0'` do.
    ///
    /// Check it before reading recovery; `privateBalanceKeys(using:expectedAddress:passphrase:path:)` throws
    /// ``PrivateBalanceError/unsupportedPath`` for any other path.
    public var hasPrivateBalanceKeys: Bool { privateBalanceAccount != nil }

    /// The account index i of a Solana account path `m/44'/501'/i'/0'`, or `nil` for any other path.
    var privateBalanceAccount: UInt32? {
        indices.count == 4 ? accountIndex : nil
    }

    /// The Ed25519 path of an account's nullifier secret, `m/44'/1392955331'/i'/1'/0'`.
    ///
    /// - Parameter account: The account index i, below 2³¹.
    /// - Returns: The path of the node whose key, without its first byte, is the nullifier secret.
    static func nullifierSecret(account: UInt32) -> Self {
        Self(indices: [44, privateBalanceCoinType, account, 1, 0])
    }

    /// The P-256 path of an account's viewing key, `m/44'/1392955331'/i'/2'/0'`.
    ///
    /// - Parameter account: The account index i, below 2³¹.
    /// - Returns: The path of the node whose key is the viewing key's scalar.
    static func viewingKey(account: UInt32) -> Self {
        Self(indices: [44, privateBalanceCoinType, account, 2, 0])
    }

    /// The Ed25519 path of an account's code root, `m/44'/1392955331'/i'/3'`.
    ///
    /// zolana uses roles 0' to 2'; role 3' is free for the wallet's one-time accounts.
    ///
    /// - Parameter account: The account index i, below 2³¹.
    /// - Returns: The path of the node whose key is the code root.
    static func codeRoot(account: UInt32) -> Self {
        Self(indices: [44, privateBalanceCoinType, account, 3])
    }
}
