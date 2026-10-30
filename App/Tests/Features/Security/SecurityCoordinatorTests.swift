import Foundation
import Testing
import Vault
import Wallet
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SecurityCoordinatorTests {
    enum Step: CaseIterable { case recovery, owner, reset }

    @Test
    func `Showing recovery opens the wallet's backup`() async throws {
        let account = try Account.fixture(index: 0)
        let recovery = try Recovery(phrase: RecoveryPhrase(RecoveryRevealTests.phrase), passphrase: "")
        let coordinator = makeCoordinator(recovery: SecurityRecoveryStore(records: [account.recoveryID: recovery]))

        coordinator.showRecovery(for: account)
        await coordinator.run(coordinator.attempt)

        #expect(coordinator.path == [.recoveryBackup])
        guard case .backup(let backup) = coordinator.backup else {
            Issue.record("Expected the wallet's backup")
            return
        }
        #expect(backup.phrase.words == recovery.phrase.words)
        #expect(coordinator.attempt == nil)
    }

    @Test(arguments: [false, true])
    func `Leaving the backup releases the words`(closesScene: Bool) async throws {
        let account = try Account.fixture(index: 0)
        let recovery = try Recovery(phrase: RecoveryPhrase(RecoveryRevealTests.phrase), passphrase: "")
        let coordinator = makeCoordinator(recovery: SecurityRecoveryStore(records: [account.recoveryID: recovery]))
        coordinator.showRecovery(for: account)
        await coordinator.run(coordinator.attempt)
        try #require(coordinator.backup != nil)

        if closesScene { coordinator.close() } else { coordinator.path.removeLast() }

        #expect(coordinator.backup == nil)
        #expect(coordinator.path.isEmpty)
    }

    @Test
    func `A standard reset confirms the owner first`() async {
        let owner = TestOwner()
        let coordinator = makeCoordinator(owner: owner)

        coordinator.startReset(.standard)
        #expect(coordinator.path.isEmpty)
        await coordinator.run(coordinator.attempt)

        #expect(coordinator.path == [.resetApp(.standard)])
        #expect(await owner.prompts == 1)
    }

    @Test
    func `A reset without recovery skips the owner check`() async {
        let owner = TestOwner()
        let coordinator = makeCoordinator(owner: owner)

        coordinator.startReset(.recoveryUnavailable)

        #expect(coordinator.path == [.resetApp(.recoveryUnavailable)])
        #expect(coordinator.attempt == nil)
        #expect(await owner.prompts == 0)
    }

    @Test
    func `Confirming the reset resets the app`() async {
        let storage = ResetStorage()
        let coordinator = makeCoordinator(storage: storage)

        coordinator.confirmReset()
        coordinator.reset()
        await coordinator.run(coordinator.attempt)

        #expect(coordinator.path == [.resetConfirmation])
        #expect(await storage.deletions == ResetStorage.Step.allCases)
        #expect(coordinator.error == nil)
    }

    @Test(arguments: Step.allCases)
    func `A failed step explains itself without moving on`(_ step: Step) async throws {
        let account = try Account.fixture(index: 0)
        let error = KeychainStoreError.authenticationFailed
        let coordinator = makeCoordinator(recovery: SecurityRecoveryStore(readError: step == .recovery ? error : nil),
                                          owner: TestOwner(error: step == .owner ? error : nil),
                                          storage: ResetStorage(failingOnce: step == .reset ? .recovery : nil))

        switch step {
        case .recovery: coordinator.showRecovery(for: account)
        case .owner: coordinator.startReset(.standard)
        case .reset: coordinator.reset()
        }
        await coordinator.run(coordinator.attempt)

        #expect(coordinator.path.isEmpty)
        #expect(coordinator.error == [.recovery: .recoveryUnreadable, .owner: .ownerNotConfirmed, .reset: .resetIncomplete][step])
        #expect(coordinator.error?.canRetry == (step == .reset))
    }

    @Test(arguments: [Step.recovery, .owner])
    func `A dismissed prompt changes nothing`(_ step: Step) async throws {
        let account = try Account.fixture(index: 0)
        let coordinator = makeCoordinator(
            recovery: SecurityRecoveryStore(readError: step == .recovery ? CancellationError() : nil),
            owner: TestOwner(error: step == .owner ? CancellationError() : nil)
        )

        if step == .recovery { coordinator.showRecovery(for: account) } else { coordinator.startReset(.standard) }
        await coordinator.run(coordinator.attempt)

        #expect(coordinator.path.isEmpty)
        #expect(coordinator.error == nil)
        #expect(coordinator.attempt == nil)
    }

    private func makeCoordinator(recovery: SecurityRecoveryStore = SecurityRecoveryStore(),
                                 owner: TestOwner = TestOwner(),
                                 storage: ResetStorage = ResetStorage()) -> SecurityCoordinator {
        SecurityCoordinator(services: SecurityServices(
            recovery: RecoveryReveal(store: recovery),
            owner: owner,
            reset: AppReset(storage: storage),
            pasteboard: NoPasteboard()
        ))
    }
}
