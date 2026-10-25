import Foundation
import Testing
import Vault
import Wallet
@testable import widgets

/// Checks how Settings > Accounts adds the wallet's next account, with public fixtures only.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AccountAdditionModelTests {
    /// Adding saves the wallet's next account, after the saved one, and reports it.
    @Test
    func `Adding saves the wallet's next account`() async throws {
        let wallet = try await PublicWalletAccounts()
        let model = AccountAdditionModel()

        model.add(to: wallet.first.recoveryID)
        #expect(model.isAdding)
        await model.run(model.attempt, creation: wallet.creation, store: wallet.store)

        let added = try #require(model.added)
        #expect(added.path == .solana(account: 1))
        #expect(added.recoveryID == wallet.first.recoveryID)
        #expect(wallet.store.accounts == [wallet.first, added])
        #expect(await wallet.storage.value == [wallet.first, added])
        #expect(await wallet.recovery.reads == [wallet.first.recoveryID])
        #expect(!model.isAdding)
        #expect(model.error == nil)
    }

    /// Taps while an addition waits are ignored, so one tap adds one account.
    @Test
    func `Taps while an addition waits are ignored`() async throws {
        let wallet = try await PublicWalletAccounts()
        let model = AccountAdditionModel()

        model.add(to: wallet.first.recoveryID)
        let attempt = model.attempt
        model.add(to: wallet.first.recoveryID)
        #expect(model.attempt == attempt)
        await model.run(attempt, creation: wallet.creation, store: wallet.store)
        await model.run(attempt, creation: wallet.creation, store: wallet.store)

        #expect(wallet.store.accounts.count == 2)
        #expect(await wallet.recovery.reads.count == 1)
    }

    /// A task that captured another attempt adds nothing.
    @Test
    func `A stale attempt adds nothing`() async throws {
        let wallet = try await PublicWalletAccounts()
        let model = AccountAdditionModel()

        model.add(to: wallet.first.recoveryID)
        await model.run(UUID(), creation: wallet.creation, store: wallet.store)
        await model.run(nil, creation: wallet.creation, store: wallet.store)

        #expect(wallet.store.accounts == [wallet.first])
        #expect(await wallet.recovery.reads.isEmpty)
        #expect(model.isAdding)
    }

    /// Cancelling authentication adds nothing and explains nothing.
    @Test
    func `Cancelled authentication adds nothing`() async throws {
        let wallet = try await PublicWalletAccounts(readError: CancellationError())
        let model = AccountAdditionModel()

        model.add(to: wallet.first.recoveryID)
        await model.run(model.attempt, creation: wallet.creation, store: wallet.store)

        #expect(wallet.store.accounts == [wallet.first])
        #expect(model.added == nil)
        #expect(model.error == nil)
        #expect(!model.isAdding)
    }

    /// Leaving the screen before the account is derived cancels the addition, which adds nothing and explains nothing.
    @Test
    func `Leaving before the account is derived adds nothing`() async throws {
        let wallet = try await PublicWalletAccounts()
        let model = AccountAdditionModel()
        model.add(to: wallet.first.recoveryID)
        let attempt = model.attempt

        let running = Task { await model.run(attempt, creation: wallet.creation, store: wallet.store) }
        running.cancel()
        await running.value

        #expect(wallet.store.accounts == [wallet.first])
        #expect(model.added == nil)
        #expect(model.error == nil)
        #expect(!model.isAdding)
    }

    /// A failed addition explains why: a missing recovery phrase, or an account that couldn't be saved.
    /// - Parameters:
    ///   - readError: The error every recovery read throws, if any.
    ///   - failsSaving: Whether the accounts can't be saved.
    ///   - error: The explained error.
    @Test(arguments: [
        (KeychainStoreError.recoveryUnavailable, false, AccountsError.recoveryUnavailable),
        (nil, true, .notAdded),
    ] as [(KeychainStoreError?, Bool, AccountsError)])
    func `A failed addition explains why`(readError: KeychainStoreError?, failsSaving: Bool,
                                          error: AccountsError) async throws {
        let wallet = try await PublicWalletAccounts(readError: readError)
        await wallet.storage.failSaving(failsSaving)
        let model = AccountAdditionModel()

        model.add(to: wallet.first.recoveryID)
        await model.run(model.attempt, creation: wallet.creation, store: wallet.store)

        #expect(model.error == error)
        #expect(model.added == nil)
        #expect(wallet.store.accounts == [wallet.first])
        #expect(await wallet.storage.value == [wallet.first])
    }

    /// Trying again after a failed save adds to the same wallet.
    @Test
    func `Trying again adds the account`() async throws {
        let wallet = try await PublicWalletAccounts()
        await wallet.storage.failSaving()
        let model = AccountAdditionModel()
        model.add(to: wallet.first.recoveryID)
        await model.run(model.attempt, creation: wallet.creation, store: wallet.store)
        await wallet.storage.failSaving(false)

        model.retry()
        await model.run(model.attempt, creation: wallet.creation, store: wallet.store)

        #expect(wallet.store.accounts.count == 2)
        #expect(model.added?.recoveryID == wallet.first.recoveryID)
    }

    /// Trying again after a missing recovery phrase does nothing, since the phrase stays missing.
    @Test
    func `A missing recovery isn't tried again`() async throws {
        let wallet = try await PublicWalletAccounts(readError: KeychainStoreError.recoveryUnavailable)
        let model = AccountAdditionModel()
        model.add(to: wallet.first.recoveryID)
        await model.run(model.attempt, creation: wallet.creation, store: wallet.store)

        model.retry()

        #expect(model.attempt == nil)
    }
}
