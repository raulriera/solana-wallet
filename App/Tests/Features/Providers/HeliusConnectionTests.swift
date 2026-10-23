import Foundation
import RPC
import Testing
@testable import widgets

/// Checks key verification outcomes through the real Helius client and local HTTP fixtures.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct HeliusConnectionTests {
    /// An accepted key is saved, and every window's provider list and portfolio hear about it.
    /// - Throws: A connection failure.
    @Test
    func `An accepted key is checked and saved`() async throws {
        let responses = HTTPResponses.keyCheck()
        let keys = StoredValue<String>()
        let revisions = ProviderRevisions()

        try await responses.connection(providerKey: keys, revisions: revisions).connect("fixture-key")

        #expect(await keys.value == "fixture-key")
        #expect(revisions.settings.value == 1)
        #expect(revisions.connection.value == 1)
        #expect(await responses.requests.count == 1)
        #expect(await responses.requests.first?.url?.query() == "api-key=fixture-key")
    }

    /// An empty key fails locally, so no request ever carries an empty key.
    @Test
    func `An empty key is rejected without contacting Helius`() async {
        let responses = HTTPResponses.keyCheck()
        let keys = StoredValue<String>()

        await #expect(throws: ProviderConnectionError.invalidKey) {
            try await responses.connection(providerKey: keys, revisions: ProviderRevisions()).connect("")
        }

        #expect(await responses.requests.isEmpty)
        #expect(await keys.value == nil)
    }

    /// Each failed check reports the cause the setup screen presents and keeps the saved key, so no window hears about
    /// a change.
    /// - Parameters:
    ///   - status: The HTTP status Helius returns.
    ///   - expected: The resulting setup failure.
    @Test(arguments: [
        (401, ProviderConnectionError.invalidKey),
        (403, ProviderConnectionError.invalidKey),
        (429, ProviderConnectionError.rateLimited),
        (500, ProviderConnectionError.unavailable),
    ])
    func `Failed checks report their cause and keep the saved key`(status: Int, expected: ProviderConnectionError) async {
        let responses = HTTPResponses.keyCheck(error: .http(statusCode: status, retryAfter: nil))
        let keys = StoredValue("saved-key")
        let revisions = ProviderRevisions()

        await #expect(throws: expected) {
            try await responses.connection(providerKey: keys, revisions: revisions).connect("fixture-key")
        }

        #expect(await responses.requests.count == 1)
        #expect(await keys.value == "saved-key")
        #expect(revisions.settings.value == 0)
        #expect(revisions.connection.value == 0)
    }

    /// A key Helius accepted still fails setup when this device can't store it.
    @Test
    func `An accepted key that can't be saved reports a storage failure`() async {
        let responses = HTTPResponses.keyCheck()
        let revisions = ProviderRevisions()

        await #expect(throws: ProviderConnectionError.storageFailed) {
            try await responses.connection(providerKey: StoredValue<String>(failsSaving: true), revisions: revisions)
                .connect("fixture-key")
        }

        #expect(revisions.settings.value == 0)
        #expect(revisions.connection.value == 0)
    }

    /// Cancelling a check reports cancellation rather than an outage, and nothing is saved.
    @Test
    func `A cancelled check reports cancellation and saves nothing`() async {
        let gate = Suspension()
        let responses = HTTPResponses.keyCheck(gate: gate)
        let keys = StoredValue<String>()
        let revisions = ProviderRevisions()
        let check = responses.connection(providerKey: keys, revisions: revisions)
        let operation = Task { try await check.connect("fixture-key") }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        operation.cancel()

        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await responses.wasCancelled)
        #expect(await keys.value == nil)
        #expect(revisions.settings.value == 0)
        #expect(revisions.connection.value == 0)
    }
}
