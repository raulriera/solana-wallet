import Foundation
import RPC
import Testing
@testable import widgets

/// Checks provider setup's key submissions through the real Helius client and local HTTP fixtures.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ProviderSetupModelTests {
    /// Each test starts from a fresh app-wide count of saved keys.
    private let revision = Revision()

    /// An accepted key is saved without the whitespace a paste can add, so the flow that asked for it can continue.
    @Test
    func `An accepted key is saved without surrounding whitespace`() async {
        let keys = StoredValue<String>()
        let submission = ProviderSetupModel(
            connection: HTTPResponses.keyCheck().connection(providerKey: keys, revision: revision))

        submission.submit(" fixture-key \n")
        await submission.run(submission.attempt)

        #expect(submission.isSaved)
        #expect(await keys.value == "fixture-key")
        #expect(submission.rejection == nil)
        #expect(submission.error == nil)
        #expect(submission.attempt == nil)
    }

    /// A rejected key keeps setup open with its inline message, and each further rejection signals again.
    @Test
    func `A rejected key shows the inline message and keeps setup open`() async {
        let responses = HTTPResponses.keyCheck(error: .http(statusCode: 401, retryAfter: nil))
        let submission = ProviderSetupModel(
            connection: responses.connection(providerKey: StoredValue<String>(), revision: revision))

        submission.submit("rejected-key")
        await submission.run(submission.attempt)

        #expect(submission.rejection == .invalidKey)
        #expect(submission.rejectionCount == 1)
        #expect(submission.error == nil)
        #expect(!submission.isSaved)
        #expect(revision.value == 0)
        submission.submit("rejected-key")
        await submission.run(submission.attempt)
        #expect(submission.rejection == .invalidKey)
        #expect(submission.rejectionCount == 2)
    }

    /// A failure other than rejection explains its cause in an alert and keeps setup open.
    @Test
    func `Failures other than rejection explain their cause in an alert`() async {
        let responses = HTTPResponses.keyCheck(error: .http(statusCode: 429, retryAfter: nil))
        let submission = ProviderSetupModel(
            connection: responses.connection(providerKey: StoredValue<String>(), revision: revision))

        submission.submit("fixture-key")
        await submission.run(submission.attempt)

        #expect(submission.error == .rateLimited)
        #expect(submission.rejection == nil)
        #expect(!submission.isSaved)
    }

    /// The rejection stays on screen while the next check runs, then gives way to that check's different failure.
    @Test
    func `A rejection changes only when the next result arrives`() async throws {
        let gate = Suspension()
        let rejecting = HTTPResponses.keyCheck(error: .http(statusCode: 401, retryAfter: nil))
        let limiting = HTTPResponses.keyCheck(error: .http(statusCode: 429, retryAfter: nil), gate: gate)
        let connection = HTTPResponses.connection(providerKey: StoredValue<String>(), revision: revision) {
            $0 == "rejected-key" ? rejecting : limiting
        }
        let submission = ProviderSetupModel(connection: connection)
        submission.submit("rejected-key")
        await submission.run(submission.attempt)
        try #require(submission.rejection == .invalidKey)

        submission.submit("limited-key")
        let attempt = try #require(submission.attempt)
        let operation = Task { await submission.run(attempt) }
        defer { operation.cancel() }
        await gate.waitUntilStarted()
        #expect(submission.rejection == .invalidKey)
        gate.resume()
        await operation.value

        #expect(submission.rejection == nil)
        #expect(submission.error == .rateLimited)
    }

    /// Taps and task reruns during a check can't replace the key being checked, which stays pending until it ends.
    @Test
    func `Taps during a check can't replace the key being checked`() async throws {
        let gate = Suspension()
        let responses = HTTPResponses.keyCheck(gate: gate)
        let keys = StoredValue<String>()
        let submission = ProviderSetupModel(
            connection: responses.connection(providerKey: keys, revision: revision))
        submission.submit("first-key")
        let attempt = try #require(submission.attempt)
        let operation = Task { await submission.run(attempt) }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        submission.submit("second-key")
        await submission.run(attempt)
        #expect(submission.attempt == attempt)
        #expect(submission.isPending)
        gate.resume()
        await operation.value

        #expect(await keys.value == "first-key")
        #expect(await responses.requests.count == 1)
        #expect(!submission.isPending)
    }

    /// Leaving setup mid-check reports nothing and keeps setup open.
    @Test
    func `A cancelled check reports nothing and keeps setup open`() async throws {
        let gate = Suspension()
        let responses = HTTPResponses.keyCheck(gate: gate)
        let submission = ProviderSetupModel(
            connection: responses.connection(providerKey: StoredValue<String>(), revision: revision))
        submission.submit("fixture-key")
        let attempt = try #require(submission.attempt)
        let operation = Task { await submission.run(attempt) }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        operation.cancel()
        await operation.value

        #expect(submission.error == nil)
        #expect(submission.rejection == nil)
        #expect(submission.attempt == nil)
        #expect(!submission.isSaved)
    }

    /// Once the key is saved, late cancellation can't undo it, so the flow can still continue.
    @Test
    func `Cancellation after the key is saved still counts the key as saved`() async throws {
        let gate = Suspension()
        let keys = StoredValue<String>(gate: gate)
        let submission = ProviderSetupModel(
            connection: HTTPResponses.keyCheck().connection(providerKey: keys, revision: revision))
        submission.submit("fixture-key")
        let attempt = try #require(submission.attempt)
        let operation = Task { await submission.run(attempt) }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        operation.cancel()
        await operation.value

        #expect(await keys.value == "fixture-key")
        #expect(submission.isSaved)
        #expect(revision.value == 1)
        #expect(submission.error == nil)
    }
}
