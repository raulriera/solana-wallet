import Foundation
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

/// Verifies that a new account comes from the wallet's own recovery, with public fixtures only.
@MainActor
struct AccountCreationTests {
    /// The new account has the address that the wallet's recovery gives at the path, a new identity, and belongs to the
    /// wallet.
    @Test
    func `A new account is derived from the wallet's recovery`() async throws {
        let wallet = try await PublicWalletAccounts()
        let recoveryID = wallet.first.recoveryID
        let path = try DerivationPath("m/44'/501'/0'")

        let account = try await wallet.creation.account(at: path, inWallet: recoveryID)

        #expect(account.address.value == PublicWallet.address)
        #expect(account.path == path)
        #expect(account.recoveryID == recoveryID)
        #expect(account.id != wallet.first.id)
        #expect(account.customName == nil)
        #expect(await wallet.recovery.reads == [recoveryID])
    }

    /// A wallet whose recovery this device no longer has gives no account.
    @Test
    func `A missing recovery gives no account`() async {
        let creation = AccountCreation(recovery: SecurityRecoveryStore(), wallet: Wallet())

        await #expect(throws: KeychainStoreError.recoveryUnavailable) {
            try await creation.account(at: .solana, inWallet: UUID())
        }
    }

    /// Cancelling authentication gives no account and reports the cancellation.
    @Test
    func `Cancelled authentication gives no account`() async {
        let creation = AccountCreation(recovery: SecurityRecoveryStore(readError: CancellationError()), wallet: Wallet())

        await #expect(throws: CancellationError.self) { try await creation.account(at: .solana, inWallet: UUID()) }
    }
}
