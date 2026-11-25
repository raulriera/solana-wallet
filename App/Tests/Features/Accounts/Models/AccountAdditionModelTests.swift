import Foundation
import Testing
import Vault
import Wallet
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AccountAdditionModelTests {
    @Test
    func `Adding saves the wallet's next account`() async throws {
        let wallet = try await ThrowawayWalletAccounts()
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

    @Test
    func `Taps while an addition waits are ignored`() async throws {
        let wallet = try await ThrowawayWalletAccounts()
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

    @Test
    func `A stale attempt adds nothing`() async throws {
        let wallet = try await ThrowawayWalletAccounts()
        let model = AccountAdditionModel()

        model.add(to: wallet.first.recoveryID)
        await model.run(UUID(), creation: wallet.creation, store: wallet.store)
        await model.run(nil, creation: wallet.creation, store: wallet.store)

        #expect(wallet.store.accounts == [wallet.first])
        #expect(await wallet.recovery.reads.isEmpty)
        #expect(model.isAdding)
    }

    @Test
    func `Cancelled authentication adds nothing`() async throws {
        let wallet = try await ThrowawayWalletAccounts(readError: CancellationError())
        let model = AccountAdditionModel()

        model.add(to: wallet.first.recoveryID)
        await model.run(model.attempt, creation: wallet.creation, store: wallet.store)

        #expect(wallet.store.accounts == [wallet.first])
        #expect(model.added == nil)
        #expect(model.error == nil)
        #expect(!model.isAdding)
    }

    @Test
    func `Leaving before the account is derived adds nothing`() async throws {
        let wallet = try await ThrowawayWalletAccounts()
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

    @Test(arguments: [
        (KeychainStoreError.recoveryUnavailable, false, AccountsError.recoveryUnavailable),
        (nil, true, .notAdded),
    ] as [(KeychainStoreError?, Bool, AccountsError)])
    func `A failed addition explains why`(readError: KeychainStoreError?, failsSaving: Bool,
                                          error: AccountsError) async throws {
        let wallet = try await ThrowawayWalletAccounts(readError: readError)
        await wallet.storage.failSaving(failsSaving)
        let model = AccountAdditionModel()

        model.add(to: wallet.first.recoveryID)
        await model.run(model.attempt, creation: wallet.creation, store: wallet.store)

        #expect(model.error == error)
        #expect(model.added == nil)
        #expect(wallet.store.accounts == [wallet.first])
        #expect(await wallet.storage.value == [wallet.first])
    }

    @Test
    func `Trying again adds the account`() async throws {
        let wallet = try await ThrowawayWalletAccounts()
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

    @Test
    func `A missing recovery isn't tried again`() async throws {
        let wallet = try await ThrowawayWalletAccounts(readError: KeychainStoreError.recoveryUnavailable)
        let model = AccountAdditionModel()
        model.add(to: wallet.first.recoveryID)
        await model.run(model.attempt, creation: wallet.creation, store: wallet.store)

        model.retry()

        #expect(model.attempt == nil)
    }
}
