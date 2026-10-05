import Foundation
import RPC
import Testing
import Wallet
@testable import widgets

/// Checks provider setup's key submissions through the real Helius client, local HTTP fixtures, and a saved fixture wallet.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ProviderSubmissionTests {
    /// A saved key ends onboarding by opening the account it was set up for.
    @Test
    func `An accepted key is saved and opens the wallet`() async throws {
        let (coordinator, router) = try await completedOnboarding()
        let keys = SavedKeys()
        let submission = ProviderSubmission(connection: HTTPResponses.keyCheck().connection(keys: keys), coordinator: coordinator)

        submission.submit("fixture-key")
        await submission.run(submission.attempt)

        let account = try #require(coordinator.account)
        #expect(router.destination == .wallet(accountID: account.id))
        #expect(await keys.saved == "fixture-key")
        #expect(!submission.isKeyRejected)
        #expect(submission.failure == nil)
        #expect(submission.attempt == nil)
    }

    /// A rejected key keeps setup open with its inline message, and each further rejection signals again.
    @Test
    func `A rejected key shows the inline message and keeps setup open`() async throws {
        let (coordinator, router) = try await completedOnboarding()
        let responses = HTTPResponses.keyCheck(failure: .http(statusCode: 401, retryAfter: nil))
        let submission = ProviderSubmission(connection: responses.connection(keys: SavedKeys()), coordinator: coordinator)

        submission.submit("rejected-key")
        await submission.run(submission.attempt)

        #expect(submission.isKeyRejected)
        #expect(submission.rejectionCount == 1)
        #expect(submission.failure == nil)
        #expect(router.destination == .onboarding)
        submission.submit("rejected-key")
        await submission.run(submission.attempt)
        #expect(submission.isKeyRejected)
        #expect(submission.rejectionCount == 2)
    }

    /// Provider failures other than rejection explain their cause in an alert.
    /// - Parameters:
    ///   - status: The HTTP status Helius returns.
    ///   - message: The alert's expected explanation.
    @Test(arguments: [
        (429, "Helius is limiting requests right now. Please try again in a moment."),
        (500, "Helius couldn't be reached. Check your connection and try again."),
    ])
    func `Failures other than rejection explain their cause in an alert`(status: Int, message: String) async throws {
        let (coordinator, router) = try await completedOnboarding()
        let responses = HTTPResponses.keyCheck(failure: .http(statusCode: status, retryAfter: nil))
        let submission = ProviderSubmission(connection: responses.connection(keys: SavedKeys()), coordinator: coordinator)

        submission.submit("fixture-key")
        await submission.run(submission.attempt)

        #expect(submission.failure.map { String(localized: $0) } == message)
        #expect(!submission.isKeyRejected)
        #expect(router.destination == .onboarding)
    }

    /// An accepted key that this device can't store keeps setup open and says so.
    @Test
    func `An accepted key that can't be saved explains the storage failure`() async throws {
        let (coordinator, router) = try await completedOnboarding()
        let submission = ProviderSubmission(connection: HTTPResponses.keyCheck().connection(keys: SavedKeys(failsSaving: true)),
                                            coordinator: coordinator)

        submission.submit("fixture-key")
        await submission.run(submission.attempt)

        #expect(submission.failure.map { String(localized: $0) } == "Your API key couldn't be saved. Please try again.")
        #expect(router.destination == .onboarding)
    }

    /// The rejection stays on screen while the next check runs, then gives way to that check's different failure.
    @Test
    func `A rejection changes only when the next result arrives`() async throws {
        let (coordinator, _) = try await completedOnboarding()
        let gate = Suspension()
        let rejecting = HTTPResponses.keyCheck(failure: .http(statusCode: 401, retryAfter: nil))
        let limiting = HTTPResponses.keyCheck(failure: .http(statusCode: 429, retryAfter: nil), gate: gate)
        let connection = HTTPResponses.connection(keys: SavedKeys()) { $0 == "rejected-key" ? rejecting : limiting }
        let submission = ProviderSubmission(connection: connection, coordinator: coordinator)
        submission.submit("rejected-key")
        await submission.run(submission.attempt)
        try #require(submission.isKeyRejected)

        submission.submit("limited-key")
        let attempt = try #require(submission.attempt)
        let operation = Task { await submission.run(attempt) }
        defer { operation.cancel() }
        await gate.waitUntilStarted()
        #expect(submission.isKeyRejected)
        gate.resume()
        await operation.value

        #expect(!submission.isKeyRejected)
        #expect(submission.failure.map { String(localized: $0) } == "Helius is limiting requests right now. Please try again in a moment.")
    }

    /// Taps and task reruns during a check can't replace the key being checked.
    @Test
    func `Taps during a check can't replace the key being checked`() async throws {
        let (coordinator, _) = try await completedOnboarding()
        let gate = Suspension()
        let responses = HTTPResponses.keyCheck(gate: gate)
        let keys = SavedKeys()
        let submission = ProviderSubmission(connection: responses.connection(keys: keys), coordinator: coordinator)
        submission.submit("first-key")
        let attempt = try #require(submission.attempt)
        let operation = Task { await submission.run(attempt) }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        submission.submit("second-key")
        await submission.run(attempt)
        #expect(submission.attempt == attempt)
        gate.resume()
        await operation.value

        #expect(await keys.saved == "first-key")
        #expect(await responses.requests.count == 1)
    }

    /// Leaving setup mid-check reports nothing and saves nothing.
    @Test
    func `A cancelled check reports nothing and keeps setup open`() async throws {
        let (coordinator, router) = try await completedOnboarding()
        let gate = Suspension()
        let responses = HTTPResponses.keyCheck(gate: gate)
        let keys = SavedKeys()
        let submission = ProviderSubmission(connection: responses.connection(keys: keys), coordinator: coordinator)
        submission.submit("fixture-key")
        let attempt = try #require(submission.attempt)
        let operation = Task { await submission.run(attempt) }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        operation.cancel()
        await operation.value

        #expect(await responses.wasCancelled)
        #expect(await keys.saved == nil)
        #expect(submission.failure == nil)
        #expect(!submission.isKeyRejected)
        #expect(submission.attempt == nil)
        #expect(router.destination == .onboarding)
    }

    /// Once the key is saved, late cancellation can't undo it, so the wallet still opens.
    @Test
    func `Cancellation after the key is saved still opens the wallet`() async throws {
        let (coordinator, router) = try await completedOnboarding()
        let gate = Suspension()
        let keys = SavedKeys(gate: gate)
        let submission = ProviderSubmission(connection: HTTPResponses.keyCheck().connection(keys: keys), coordinator: coordinator)
        submission.submit("fixture-key")
        let attempt = try #require(submission.attempt)
        let operation = Task { await submission.run(attempt) }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        operation.cancel()
        await operation.value

        let account = try #require(coordinator.account)
        #expect(await keys.saved == "fixture-key")
        #expect(router.destination == .wallet(accountID: account.id))
        #expect(submission.failure == nil)
    }

    /// Saves a public fixture wallet so provider setup has an account to open.
    /// - Returns: The window's coordinator after completion, and the router it opens the wallet with.
    /// - Throws: A preparation or storage failure.
    private func completedOnboarding() async throws -> (OnboardingCoordinator, WindowRouter) {
        let recovery = OnboardingRecoveryStore()
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(),
                                                recovery: recovery, accounts: OnboardingAccountStore(recovery: recovery), router: router)
        try await coordinator.importRecovery(OnboardingCoordinatorTests.phrase, passphrase: "")
        _ = try await coordinator.complete()
        return (coordinator, router)
    }
}
