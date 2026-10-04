import Foundation
import Testing
import Vault
import Wallet
@testable import widgets

extension ImportSubmissionTests {
    /// A disappearing destination can finish its transition after another presentation begins.
    @Test
    func `Late disappearance from a previous presentation cannot cancel the next import`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        let submission = ImportSubmission(coordinator: coordinator)
        submission.present()
        let oldPresentation = submission.presentationID
        submission.isPresented = false
        submission.present()
        submission.submit(OnboardingCoordinatorTests.phrase, passphrase: "TREZOR")
        let attempt = submission.attempt

        submission.leave(oldPresentation)

        #expect(submission.isPresented)
        #expect(submission.attempt == attempt)
        await submission.run(attempt)
        #expect(coordinator.account != nil)
    }

    /// Cleanup keeps ownership until derivation unwinds, including before SwiftUI delivers cancellation.
    /// - Parameter deliversCancellation: Whether the view task has received its cancellation signal.
    @Test(arguments: [true, false])
    func `Back during preparation blocks reopening until the attempt has unwound`(deliversCancellation: Bool) async throws {
        let gate = Suspension()
        let http = HTTPResponses.discovery(gate: gate)
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: http.client), wallet: Wallet(), recovery: recovery,
                                                accounts: accounts, router: router)
        let submission = ImportSubmission(coordinator: coordinator)
        submission.present()
        submission.submit(OnboardingCoordinatorTests.phrase, passphrase: "TREZOR")
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
        #expect(submission.failure == nil)
        #expect(!submission.isPending)
        #expect(await recovery.saves.isEmpty)
        #expect(await http.requests.count == 1)
        #expect(await http.wasCancelled == deliversCancellation)
        submission.present()
        #expect(submission.isPresented)
    }

    /// A committed recovery survives Back, and no metadata is saved after cancellation is observed.
    @Test
    func `Back during recovery persistence preserves its write and releases only the draft`() async throws {
        let gate = Suspension()
        let recovery = OnboardingRecoveryStore(gate: gate)
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        let submission = ImportSubmission(coordinator: coordinator)
        submission.present()
        submission.submit(OnboardingCoordinatorTests.phrase, passphrase: "TREZOR")
        let attempt = submission.attempt
        let operation = Task { await submission.run(attempt) }
        defer { operation.cancel() }
        await gate.waitUntilStarted()
        let retainedID = try #require(await recovery.saves.first)

        submission.isPresented = false
        operation.cancel()
        await operation.value

        #expect(await recovery.contains(retainedID))
        #expect(await accounts.additions.isEmpty)
        #expect(coordinator.recovery == nil)
        #expect(submission.failure == nil)
        #expect(router.destination == .onboarding)
    }

    /// A dependency cancellation while the screen remains open permits retry of the prepared draft.
    @Test
    func `Cancelled authentication retains the prepared import for an explicit retry`() async throws {
        let recovery = OnboardingRecoveryStore(firstFailure: CancellationError(), commitBeforeFailure: true)
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        let submission = ImportSubmission(coordinator: coordinator)
        submission.present()
        submission.submit(OnboardingCoordinatorTests.phrase, passphrase: "TREZOR")
        await submission.run(submission.attempt)
        let retainedID = try #require(await recovery.saves.first)
        #expect(submission.failure == nil)
        #expect(coordinator.recovery != nil)

        submission.submit(OnboardingCoordinatorTests.phrase, passphrase: "TREZOR")
        await submission.run(submission.attempt)

        #expect(coordinator.account?.recoveryID == retainedID)
        #expect(await recovery.reads == [retainedID])
        #expect(await accounts.records.count == 1)
    }

    /// Leaving after commit cannot turn saved onboarding into a failure or affect another window.
    @Test
    func `Late cancellation preserves successful routing and another windows prepared draft`() async throws {
        let gate = Suspension()
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery, gate: gate)
        let router = WindowRouter(initialDestination: .onboarding)
        let otherRouter = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        let other = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: otherRouter)
        try await other.importRecovery(OnboardingCoordinatorTests.phrase, passphrase: "other-window")
        let submission = ImportSubmission(coordinator: coordinator)
        submission.present()
        submission.submit(OnboardingCoordinatorTests.phrase, passphrase: "TREZOR")
        let attempt = submission.attempt
        let operation = Task { await submission.run(attempt) }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        submission.isPresented = false
        operation.cancel()
        await operation.value

        let account = try #require(await accounts.records.first)
        #expect(router.destination == .wallet(accountID: account.id))
        #expect(await recovery.contains(account.recoveryID))
        #expect(submission.failure == nil)
        #expect(other.recovery?.passphrase == "other-window")
        #expect(otherRouter.destination == .onboarding)
    }
}
