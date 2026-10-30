extension Wallet: PrivateBalanceKeyDeriving {
    @concurrent
    public func privateBalanceKeys(
        using phrase: RecoveryPhrase,
        expectedAddress: String,
        passphrase: String,
        path: DerivationPath
    ) async throws -> PrivateBalanceKeys {
        try Task.checkCancellation()
        guard let account = path.privateBalanceAccount else { throw PrivateBalanceError.unsupportedPath }
        let keys = try Self.withVerifiedAccount(
            phrase, passphrase: passphrase, path: path, expectedAddress: expectedAddress,
            mismatch: PrivateBalanceError.accountMismatch
        ) { _, seed in
            try PrivateBalanceKeys(seed: seed, account: account)
        }
        try Task.checkCancellation()
        return keys
    }
}
