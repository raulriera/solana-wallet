import Foundation
import RPC
import Testing
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct HeliusConnectionTests {
    @Test
    func `An accepted key is checked and saved`() async throws {
        let responses = HTTPResponses.keyCheck()
        let keys = StoredValue<String>()
        let providers = ProviderStore.inMemory(key: keys)

        try await responses.connection(providers: providers).connect("fixture-key")

        #expect(await keys.value == "fixture-key")
        #expect(providers.keyPreview == "fixt•••••••")
        #expect(await responses.requests.count == 1)
        #expect(await responses.requests.first?.url?.query() == "api-key=fixture-key")
    }

    @Test
    func `An empty key is rejected without contacting Helius`() async {
        let responses = HTTPResponses.keyCheck()
        let keys = StoredValue<String>()

        await #expect(throws: ProviderConnectionError.invalidKey) {
            try await responses.connection(providers: .inMemory(key: keys)).connect("")
        }

        #expect(await responses.requests.isEmpty)
        #expect(await keys.value == nil)
    }

    @Test(arguments: [
        (401, ProviderConnectionError.invalidKey),
        (403, ProviderConnectionError.invalidKey),
        (429, ProviderConnectionError.rateLimited),
        (500, ProviderConnectionError.unavailable),
    ])
    func `Failed checks report their cause and keep the saved key`(status: Int, expected: ProviderConnectionError) async {
        let responses = HTTPResponses.keyCheck(error: .http(statusCode: status, retryAfter: nil))
        let keys = StoredValue("saved-key")
        let providers = ProviderStore.inMemory(key: keys)

        await #expect(throws: expected) {
            try await responses.connection(providers: providers).connect("fixture-key")
        }

        #expect(await responses.requests.count == 1)
        #expect(await keys.value == "saved-key")
        await providers.load()
        #expect(providers.keyPreview == "save•••••")
    }

    @Test
    func `An accepted key that can't be saved reports a storage failure`() async {
        let responses = HTTPResponses.keyCheck()
        let providers = ProviderStore.inMemory(key: StoredValue(failsSaving: true))

        await #expect(throws: ProviderConnectionError.storageFailed) {
            try await responses.connection(providers: providers).connect("fixture-key")
        }

        #expect(providers.keyPreview == nil)
    }

    @Test
    func `A cancelled check reports cancellation and saves nothing`() async {
        let gate = Suspension()
        let responses = HTTPResponses.keyCheck(gate: gate)
        let keys = StoredValue<String>()
        let providers = ProviderStore.inMemory(key: keys)
        let check = responses.connection(providers: providers)
        let operation = Task { try await check.connect("fixture-key") }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        operation.cancel()

        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await responses.wasCancelled)
        #expect(await keys.value == nil)
        #expect(providers.keyPreview == nil)
    }
}
