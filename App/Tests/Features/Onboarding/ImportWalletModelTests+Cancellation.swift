import Foundation
import Testing
import Vault
import Wallet
@testable import widgets

extension ImportWalletModelTests {
    @Test
    func `Late disappearance from a previous presentation cannot cancel the next import`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        let submission = ImportWalletModel(coordinator: coordinator)
        submission.present()
        let oldPresentation = submission.presentationID
        submission.isPresented = false
        submission.present()
        submission.submit(ThrowawayWallet.words, passphrase: "TREZOR")
        let attempt = submission.attempt

        submission.leave(oldPresentation)

        #expect(submission.isPresented)
        #expect(submission.attempt == attempt)
        await submission.run(attempt)
        #expect(coordinator.account != nil)
    }

    @Test(arguments: [true, false])
    func `Back during preparation blocks reopening until the attempt has unwound`(deliversCancellation: Bool) async throws {
        let gate = Suspension()
        let http = HTTPResponses.discovery(gate: gate)
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: http.client), wallet: Wallet(), recovery: recovery,
                                                accounts: accounts)
        let submission = ImportWalletModel(coordinator: coordinator)
        submission.present()
        submission.submit(ThrowawayWallet.words, passphrase: "TREZOR")
        let attempt = submission.attempt
        let operation = Task { await submission.run(attempt) }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        submission.isPresented = false
        submission.present()
        #expect(!submission.isPresented)
        #expect(submission.isPending)
        if deliversCancellation { operation.cancel() }
        else { gate.resume() }
        await operation.value

        #expect(coordinator.recovery == nil)
        #expect(submission.error == nil)
        #expect(!submission.isPending)
        #expect(await recovery.saves.isEmpty)
        #expect(await http.requests.count == 1)
        #expect(await http.wasCancelled == deliversCancellation)
        submission.present()
        #expect(submission.isPresented)
    }

    @Test
    func `Back during recovery persistence preserves its write and releases only the draft`() async throws {
        let gate = Suspension()
        let recovery = OnboardingRecoveryStore(gate: gate)
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        let submission = ImportWalletModel(coordinator: coordinator)
        submission.present()
        submission.submit(ThrowawayWallet.words, passphrase: "TREZOR")
        let attempt = submission.attempt
        let operation = Task { await submission.run(attempt) }
        defer { operation.cancel() }
        await gate.waitUntilStarted()
        let retainedID = try #require(await recovery.saves.first)

        submission.isPresented = false
        operation.cancel()
        await operation.value

        #expect(await recovery.contains(retainedID))
        #expect(accounts.accounts.isEmpty)
        #expect(coordinator.recovery == nil)
        #expect(submission.error == nil)
        #expect(coordinator.finishedAccount == nil)
    }

    @Test
    func `Cancelled authentication retains the prepared import for an explicit retry`() async throws {
        let recovery = OnboardingRecoveryStore(firstError: CancellationError(), commitBeforeError: true)
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        let submission = ImportWalletModel(coordinator: coordinator)
        submission.present()
        submission.submit(ThrowawayWallet.words, passphrase: "TREZOR")
        await submission.run(submission.attempt)
        let retainedID = try #require(await recovery.saves.first)
        #expect(submission.error == nil)
        #expect(coordinator.recovery != nil)

        submission.submit(ThrowawayWallet.words, passphrase: "TREZOR")
        await submission.run(submission.attempt)

        #expect(coordinator.account?.recoveryID == retainedID)
        #expect(await recovery.reads == [retainedID])
        #expect(accounts.accounts.count == 1)
    }

    @Test
    func `Late cancellation keeps the saved account and another windows prepared draft`() async throws {
        let gate = Suspension()
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory(StoredValue(gate: gate))
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        let other = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        try await other.importRecovery(ThrowawayWallet.words, passphrase: "other-window")
        let submission = ImportWalletModel(coordinator: coordinator)
        submission.present()
        submission.submit(ThrowawayWallet.words, passphrase: "TREZOR")
        let attempt = submission.attempt
        let operation = Task { await submission.run(attempt) }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        submission.isPresented = false
        operation.cancel()
        gate.resume()
        await operation.value

        let account = try #require(accounts.accounts.first)
        #expect(coordinator.account?.id == account.id)
        #expect(await recovery.contains(account.recoveryID))
        #expect(submission.error == nil)
        #expect(other.recovery?.passphrase == "other-window")
        #expect(other.finishedAccount == nil)
    }
}
