import Foundation
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

@MainActor
struct AccountCreationTests {
    @Test
    func `A new account is derived from the wallet's recovery`() async throws {
        let wallet = try await ThrowawayWalletAccounts()
        let recoveryID = wallet.first.recoveryID
        let path = try DerivationPath("m/44'/501'/0'")

        let account = try await wallet.creation.account(at: path, inWallet: recoveryID)

        #expect(account.address.value == ThrowawayWallet.address)
        #expect(account.path == path)
        #expect(account.recoveryID == recoveryID)
        #expect(account.id != wallet.first.id)
        #expect(account.customName == nil)
        #expect(await wallet.recovery.reads == [recoveryID])
    }

    @Test
    func `A missing recovery or cancelled authentication gives no account`() async {
        let missing = AccountCreation(recovery: SecurityRecoveryStore(), wallet: Wallet())
        let cancelled = AccountCreation(
            recovery: SecurityRecoveryStore(readError: CancellationError()), wallet: Wallet())

        await #expect(throws: KeychainStoreError.recoveryUnavailable) {
            try await missing.account(at: .solana, inWallet: UUID())
        }
        await #expect(throws: CancellationError.self) { try await cancelled.account(at: .solana, inWallet: UUID()) }
    }
}
