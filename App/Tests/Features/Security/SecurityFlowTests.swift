import Foundation
import Testing
import Vault
import Wallet
@testable import widgets

/// Verifies Security & Privacy navigation and steps with public fixtures and in-memory stores.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SecurityFlowTests {
    /// A step that can fail on its way to the next screen.
    enum Step: CaseIterable { case recovery, owner, reset }

    /// Reading the recovery opens its backup.
    @Test
    func `Showing recovery opens the wallet's backup`() async throws {
        let account = try Account.fixture(index: 0)
        let recovery = try Recovery(phrase: RecoveryPhrase(RecoveryRevealTests.phrase), passphrase: "")
        let flow = makeFlow(recovery: SecurityRecoveryStore(records: [account.recoveryID: recovery]))

        flow.showRecovery(for: account)
        await flow.run(flow.attempt)

        #expect(flow.path == [.recoveryBackup])
        guard case .backup(let backup) = flow.backup else {
            Issue.record("Expected the wallet's backup")
            return
        }
        #expect(backup.phrase.words == recovery.phrase.words)
        #expect(flow.attempt == nil)
    }

    /// Leaving the backup screen, or the whole scene, releases the words.
    /// - Parameter closesScene: Whether the scene leaves instead of only the backup screen.
    @Test(arguments: [false, true])
    func `Leaving the backup releases the words`(closesScene: Bool) async throws {
        let account = try Account.fixture(index: 0)
        let recovery = try Recovery(phrase: RecoveryPhrase(RecoveryRevealTests.phrase), passphrase: "")
        let flow = makeFlow(recovery: SecurityRecoveryStore(records: [account.recoveryID: recovery]))
        flow.showRecovery(for: account)
        await flow.run(flow.attempt)
        try #require(flow.backup != nil)

        if closesScene { flow.close() } else { flow.path.removeLast() }

        #expect(flow.backup == nil)
        #expect(flow.path.isEmpty)
    }

    /// A standard reset asks the device owner before explaining the reset.
    @Test
    func `A standard reset confirms the owner first`() async {
        let owner = TestOwner()
        let flow = makeFlow(owner: owner)

        flow.startReset(.standard)
        #expect(flow.path.isEmpty)
        await flow.run(flow.attempt)

        #expect(flow.path == [.resetApp(.standard)])
        #expect(await owner.prompts == 1)
    }

    /// Without recovery there's nothing to unlock, so the reset explanation opens at once.
    @Test
    func `A reset without recovery skips the owner check`() async {
        let owner = TestOwner()
        let flow = makeFlow(owner: owner)

        flow.startReset(.recoveryUnavailable)

        #expect(flow.path == [.resetApp(.recoveryUnavailable)])
        #expect(flow.attempt == nil)
        #expect(await owner.prompts == 0)
    }

    /// Confirming the reset deletes everything and tells every window.
    @Test
    func `Confirming the reset resets the app`() async {
        let storage = ResetStorage()
        let revision = AppResetRevision()
        let flow = makeFlow(storage: storage, revision: revision)

        flow.confirmReset()
        flow.reset()
        await flow.run(flow.attempt)

        #expect(flow.path == [.resetConfirmation])
        #expect(await storage.deletions == [.recovery, .wallets, .key])
        #expect(revision.value == 1)
        #expect(flow.error == nil)
    }

    /// A failed step explains itself and stays on the current screen.
    /// - Parameter step: The step that fails.
    @Test(arguments: Step.allCases)
    func `A failed step explains itself without moving on`(_ step: Step) async throws {
        let account = try Account.fixture(index: 0)
        let error = KeychainStoreError.authenticationFailed
        let flow = makeFlow(recovery: SecurityRecoveryStore(readError: step == .recovery ? error : nil),
                            owner: TestOwner(error: step == .owner ? error : nil),
                            storage: ResetStorage(failingOnce: step == .reset ? .recovery : nil))

        switch step {
        case .recovery: flow.showRecovery(for: account)
        case .owner: flow.startReset(.standard)
        case .reset: flow.reset()
        }
        await flow.run(flow.attempt)

        #expect(flow.path.isEmpty)
        #expect(flow.error == [.recovery: .recoveryUnreadable, .owner: .ownerNotConfirmed, .reset: .resetIncomplete][step])
    }

    /// Dismissing the system prompt changes nothing.
    /// - Parameter step: The step whose prompt is dismissed.
    @Test(arguments: [Step.recovery, .owner])
    func `A dismissed prompt changes nothing`(_ step: Step) async throws {
        let account = try Account.fixture(index: 0)
        let flow = makeFlow(recovery: SecurityRecoveryStore(readError: step == .recovery ? CancellationError() : nil),
                            owner: TestOwner(error: step == .owner ? CancellationError() : nil))

        if step == .recovery { flow.showRecovery(for: account) } else { flow.startReset(.standard) }
        await flow.run(flow.attempt)

        #expect(flow.path.isEmpty)
        #expect(flow.error == nil)
        #expect(flow.attempt == nil)
    }

    /// Creates a flow around in-memory stores.
    /// - Parameters:
    ///   - recovery: The recovery storage that the reveal reads.
    ///   - owner: The device-owner check.
    ///   - storage: The stores that a reset empties.
    ///   - revision: Counts finished resets.
    /// - Returns: A flow with an empty path.
    private func makeFlow(recovery: SecurityRecoveryStore = SecurityRecoveryStore(), owner: TestOwner = TestOwner(),
                          storage: ResetStorage = ResetStorage(), revision: AppResetRevision = AppResetRevision()) -> SecurityFlow {
        SecurityFlow(services: SecurityServices(
            recovery: RecoveryReveal(store: recovery),
            owner: owner,
            reset: AppReset(recovery: storage, accounts: storage, providerKeys: storage, revision: revision),
            pasteboard: NoPasteboard()
        ))
    }
}
