import Privacy
import Transactions
import Wallet

extension OneTimeAccount {
    /// The one-time account's Solana Rings keys, which receive a redeem code's note and spend it.
    ///
    /// - Throws: ``Transactions/ValidationError/invalidAddress`` for an invalid address, which a 32-byte public key
    ///   prevents, or Privacy's validation error for a nullifier secret that isn't 31 bytes, which derivation prevents.
    nonisolated var shieldedAccount: ShieldedAccount {
        get throws {
            try ShieldedAccount(signingAddress: Address(address), nullifierSecret: privateBalanceKeys.nullifierSecret,
                                viewingKey: privateBalanceKeys.viewingKey)
        }
    }
}
