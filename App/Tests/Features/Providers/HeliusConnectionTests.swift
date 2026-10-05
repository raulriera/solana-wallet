import Foundation
import RPC
import Testing
@testable import widgets

/// Checks key verification outcomes through the real Helius client and local HTTP fixtures.
@Suite(.timeLimit(.minutes(1)))
struct HeliusConnectionTests {
    /// Surrounding whitespace from a paste never reaches Helius or storage.
    /// - Throws: A connection failure.
    @Test
    func `An accepted key is checked and saved without surrounding whitespace`() async throws {
        let responses = HTTPResponses.keyCheck()
        let keys = SavedKeys()

        try await responses.connection(keys: keys).connect(apiKey: " fixture-key \n")

        #expect(await keys.saved == "fixture-key")
        #expect(await responses.requests.count == 1)
        #expect(await responses.requests.first?.url?.query() == "api-key=fixture-key")
    }

    /// Blank input fails locally, so no request ever carries an empty key.
    @Test
    func `Blank input is rejected without contacting Helius`() async {
        let responses = HTTPResponses.keyCheck()
        let keys = SavedKeys()

        await #expect(throws: ProviderConnectionError.invalidKey) {
            try await responses.connection(keys: keys).connect(apiKey: " \n ")
        }

        #expect(await responses.requests.isEmpty)
        #expect(await keys.saved == nil)
    }

    /// Each failed check reports the cause the setup screen presents, and nothing is saved.
    /// - Parameters:
    ///   - status: The HTTP status Helius returns.
    ///   - expected: The resulting setup failure.
    @Test(arguments: [
        (401, ProviderConnectionError.invalidKey),
        (403, ProviderConnectionError.invalidKey),
        (429, ProviderConnectionError.rateLimited),
        (500, ProviderConnectionError.unavailable),
    ])
    func `Failed checks report their cause and save nothing`(status: Int, expected: ProviderConnectionError) async {
        let responses = HTTPResponses.keyCheck(failure: .http(statusCode: status, retryAfter: nil))
        let keys = SavedKeys()

        await #expect(throws: expected) {
            try await responses.connection(keys: keys).connect(apiKey: "fixture-key")
        }

        #expect(await responses.requests.count == 1)
        #expect(await keys.saved == nil)
    }

    /// A key Helius accepted still fails setup when this device can't store it.
    @Test
    func `An accepted key that can't be saved reports a storage failure`() async {
        let responses = HTTPResponses.keyCheck()

        await #expect(throws: ProviderConnectionError.storageFailed) {
            try await responses.connection(keys: SavedKeys(failsSaving: true)).connect(apiKey: "fixture-key")
        }
    }

    /// Cancelling a check reports cancellation rather than an outage, and nothing is saved.
    @Test
    func `A cancelled check reports cancellation and saves nothing`() async {
        let gate = Suspension()
        let responses = HTTPResponses.keyCheck(gate: gate)
        let keys = SavedKeys()
        let check = responses.connection(keys: keys)
        let operation = Task { try await check.connect(apiKey: "fixture-key") }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        operation.cancel()

        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await responses.wasCancelled)
        #expect(await keys.saved == nil)
    }
}
