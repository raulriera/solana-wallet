import Foundation
import RPC
import Testing
@testable import widgets

/// Checks provider setup's key submissions through the real Helius client and local HTTP fixtures.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ProviderSubmissionTests {
    /// Each test starts from a fresh app-wide count of saved keys.
    private let revision = Revision()

    /// An accepted key is saved, so the flow that asked for it can continue.
    @Test
    func `An accepted key is saved`() async {
        let keys = SavedKeys()
        let submission = ProviderSubmission(connection: HTTPResponses.keyCheck().connection(keys: keys), revision: revision)

        submission.submit("fixture-key")
        await submission.run(submission.attempt)

        #expect(submission.isSaved)
        #expect(revision.value == 1)
        #expect(await keys.saved == "fixture-key")
        #expect(!submission.isKeyRejected)
        #expect(submission.error == nil)
        #expect(submission.attempt == nil)
    }

    /// A rejected key keeps setup open with its inline message, and each further rejection signals again.
    @Test
    func `A rejected key shows the inline message and keeps setup open`() async {
        let responses = HTTPResponses.keyCheck(error: .http(statusCode: 401, retryAfter: nil))
        let submission = ProviderSubmission(connection: responses.connection(keys: SavedKeys()), revision: revision)

        submission.submit("rejected-key")
        await submission.run(submission.attempt)

        #expect(submission.isKeyRejected)
        #expect(submission.rejectionCount == 1)
        #expect(submission.error == nil)
        #expect(!submission.isSaved)
        #expect(revision.value == 0)
        submission.submit("rejected-key")
        await submission.run(submission.attempt)
        #expect(submission.isKeyRejected)
        #expect(submission.rejectionCount == 2)
    }

    /// Provider failures other than rejection explain their cause in an alert.
    /// - Parameters:
    ///   - status: The HTTP status Helius returns.
    ///   - expected: The error the alert explains.
    @Test(arguments: [
        (429, ProviderConnectionError.rateLimited),
        (500, .unavailable),
    ])
    func `Failures other than rejection explain their cause in an alert`(status: Int, expected: ProviderConnectionError) async {
        let responses = HTTPResponses.keyCheck(error: .http(statusCode: status, retryAfter: nil))
        let submission = ProviderSubmission(connection: responses.connection(keys: SavedKeys()), revision: revision)

        submission.submit("fixture-key")
        await submission.run(submission.attempt)

        #expect(submission.error == expected)
        #expect(!submission.isKeyRejected)
        #expect(!submission.isSaved)
    }

    /// An accepted key that this device can't store keeps setup open and says so.
    @Test
    func `An accepted key that can't be saved explains the storage failure`() async {
        let submission = ProviderSubmission(connection: HTTPResponses.keyCheck().connection(keys: SavedKeys(failsSaving: true)), revision: revision)

        submission.submit("fixture-key")
        await submission.run(submission.attempt)

        #expect(submission.error == .storageFailed)
        #expect(!submission.isSaved)
    }

    /// The rejection stays on screen while the next check runs, then gives way to that check's different failure.
    @Test
    func `A rejection changes only when the next result arrives`() async throws {
        let gate = Suspension()
        let rejecting = HTTPResponses.keyCheck(error: .http(statusCode: 401, retryAfter: nil))
        let limiting = HTTPResponses.keyCheck(error: .http(statusCode: 429, retryAfter: nil), gate: gate)
        let connection = HTTPResponses.connection(keys: SavedKeys()) { $0 == "rejected-key" ? rejecting : limiting }
        let submission = ProviderSubmission(connection: connection, revision: revision)
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
        #expect(submission.error == .rateLimited)
    }

    /// Taps and task reruns during a check can't replace the key being checked.
    @Test
    func `Taps during a check can't replace the key being checked`() async throws {
        let gate = Suspension()
        let responses = HTTPResponses.keyCheck(gate: gate)
        let keys = SavedKeys()
        let submission = ProviderSubmission(connection: responses.connection(keys: keys), revision: revision)
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
        let gate = Suspension()
        let responses = HTTPResponses.keyCheck(gate: gate)
        let keys = SavedKeys()
        let submission = ProviderSubmission(connection: responses.connection(keys: keys), revision: revision)
        submission.submit("fixture-key")
        let attempt = try #require(submission.attempt)
        let operation = Task { await submission.run(attempt) }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        operation.cancel()
        await operation.value

        #expect(await responses.wasCancelled)
        #expect(await keys.saved == nil)
        #expect(submission.error == nil)
        #expect(!submission.isKeyRejected)
        #expect(submission.attempt == nil)
        #expect(!submission.isSaved)
    }

    /// Once the key is saved, late cancellation can't undo it, so the flow can still continue.
    @Test
    func `Cancellation after the key is saved still counts the key as saved`() async throws {
        let gate = Suspension()
        let keys = SavedKeys(gate: gate)
        let submission = ProviderSubmission(connection: HTTPResponses.keyCheck().connection(keys: keys), revision: revision)
        submission.submit("fixture-key")
        let attempt = try #require(submission.attempt)
        let operation = Task { await submission.run(attempt) }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        operation.cancel()
        await operation.value

        #expect(await keys.saved == "fixture-key")
        #expect(submission.isSaved)
        #expect(revision.value == 1)
        #expect(submission.error == nil)
    }
}
