import Foundation
import RPC
import Testing
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ProviderSetupModelTests {
    @Test
    func `An accepted key is saved without surrounding whitespace`() async {
        let keys = StoredValue<String>()
        let submission = ProviderSetupModel(
            connection: HTTPResponses.keyCheck().connection(rpcStore: .inMemory(key: keys)))

        submission.submit(" fixture-key \n")
        await submission.run(submission.attempt)

        #expect(submission.isSaved)
        #expect(await keys.value == "fixture-key")
        #expect(submission.rejection == nil)
        #expect(submission.error == nil)
        #expect(submission.attempt == nil)
    }

    @Test
    func `A rejected key shows the inline message and keeps setup open`() async {
        let responses = HTTPResponses.keyCheck(error: .http(statusCode: 401, retryAfter: nil))
        let submission = ProviderSetupModel(
            connection: responses.connection(rpcStore: .inMemory()))

        submission.submit("rejected-key")
        await submission.run(submission.attempt)

        #expect(submission.rejection == .invalidKey)
        #expect(submission.rejectionCount == 1)
        #expect(submission.error == nil)
        #expect(!submission.isSaved)
        submission.submit("rejected-key")
        await submission.run(submission.attempt)
        #expect(submission.rejection == .invalidKey)
        #expect(submission.rejectionCount == 2)
    }

    @Test
    func `A rejection changes only when the next result arrives`() async throws {
        let gate = Suspension()
        let rejecting = HTTPResponses.keyCheck(error: .http(statusCode: 401, retryAfter: nil))
        let limiting = HTTPResponses.keyCheck(error: .http(statusCode: 429, retryAfter: nil), gate: gate)
        let connection = HTTPResponses.connection(rpcStore: .inMemory()) {
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

    @Test
    func `Taps during a check can't replace the key being checked`() async throws {
        let gate = Suspension()
        let responses = HTTPResponses.keyCheck(gate: gate)
        let keys = StoredValue<String>()
        let submission = ProviderSetupModel(
            connection: responses.connection(rpcStore: .inMemory(key: keys)))
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

    @Test
    func `A cancelled check reports nothing and keeps setup open`() async throws {
        let gate = Suspension()
        let responses = HTTPResponses.keyCheck(gate: gate)
        let submission = ProviderSetupModel(
            connection: responses.connection(rpcStore: .inMemory()))
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

    @Test
    func `Cancellation after the key is saved still counts the key as saved`() async throws {
        let gate = Suspension()
        let keys = StoredValue<String>(gate: gate)
        let submission = ProviderSetupModel(
            connection: HTTPResponses.keyCheck().connection(rpcStore: .inMemory(key: keys)))
        submission.submit("fixture-key")
        let attempt = try #require(submission.attempt)
        let operation = Task { await submission.run(attempt) }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        operation.cancel()
        gate.resume()
        await operation.value

        #expect(await keys.value == "fixture-key")
        #expect(submission.isSaved)
        #expect(submission.error == nil)
    }
}
