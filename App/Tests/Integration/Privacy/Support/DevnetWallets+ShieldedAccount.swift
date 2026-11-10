import Privacy
import Transactions
import Vault
import Wallet
@testable import widgets

extension DevnetWallets {
    func shieldedAccount(of account: widgets.Account) async throws -> ShieldedAccount {
        try PrivateBalanceKeyRecord(try await Wallet().privateBalanceKeys(
            using: recovery.phrase, expectedAddress: account.address.value, passphrase: recovery.passphrase,
            path: account.path
        )).shieldedAccount(for: account.address)
    }
}
