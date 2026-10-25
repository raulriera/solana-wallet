import Privacy
import Transactions
import Wallet

extension OneTimeAccount {
    /// The one-time account's Solana Rings keys, which receive a redeem code's note and spend it.
    ///
    /// - Throws: An address or key-length error, which derivation prevents.
    nonisolated var shieldedAccount: ShieldedAccount {
        get throws {
            try ShieldedAccount(signingAddress: Address(address), nullifierSecret: privateBalanceKeys.nullifierSecret,
                                viewingKey: privateBalanceKeys.viewingKey)
        }
    }
}
