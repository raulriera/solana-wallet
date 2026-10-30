import Privacy
import Transactions
import Wallet

extension OneTimeAccount {
    /// The one-time account's shielded keys.
    ///
    /// - Throws: A validation error for an invalid address or nullifier secret.
    nonisolated var shieldedAccount: ShieldedAccount {
        get throws {
            try ShieldedAccount(signingAddress: Address(address), nullifierSecret: privateBalanceKeys.nullifierSecret,
                                viewingKey: privateBalanceKeys.viewingKey)
        }
    }
}
