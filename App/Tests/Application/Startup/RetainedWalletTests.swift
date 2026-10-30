import Foundation
import Storage
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

struct RetainedWalletTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VERIFY_RETAINED_WALLET"] == "1"))
    func `Saved wallets remain recoverable after an app update`() async throws {
        let file = AccountStore.file(in: .persistentDirectory.appending(path: "Accounts", directoryHint: .isDirectory))
        let accounts = try await file.load() ?? []
        try #require(!accounts.isEmpty, "This check requires a retained wallet")
        let store = KeychainStore(service: "com.raulriera.widgets.recovery")
        for account in accounts {
            let recovery = try await store.recovery(for: account.recoveryID,
                reason: "Verify saved wallet after installing an update")
            let derived = try await Wallet().accounts(for: recovery.phrase,
                passphrase: recovery.passphrase, paths: [account.path])
            let matchesSavedAddress = derived.map(\.address) == [account.address.value]
            #expect(matchesSavedAddress)
        }
    }
}
