import Foundation
@testable import RPC
import Synchronization
import Testing
@testable import widgets

/// Checks that requests use the key saved when they're sent, through the real Helius client and local HTTP fixtures.
@Suite(.timeLimit(.minutes(1)))
struct HeliusClientTests {
    /// Without a saved key, requests and subscriptions fail before anything reaches Helius.
    @Test
    func `A missing key fails before contacting Helius`() async {
        let responses = HTTPResponses.keyCheck()
        let client = responses.heliusClient(keys: SavedKeys())

        await #expect(throws: HeliusClient.Failure.missingKey) { _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset)) }
        await #expect(throws: HeliusClient.Failure.missingKey) { _ = try await client.changedSlots(for: [PublicWallet.address]) }
        #expect(await responses.requests.isEmpty)
    }

    /// Helius rejecting the saved key is reported as a typed failure, never as a generic HTTP error.
    /// - Parameter status: The HTTP status Helius returns.
    @Test(arguments: [401, 403])
    func `A rejected key is reported as a key failure`(status: Int) async throws {
        let responses = HTTPResponses.keyCheck(failure: .http(statusCode: status, retryAfter: nil))
        let keys = SavedKeys()
        try await keys.save("rejected-key")

        await #expect(throws: HeliusClient.Failure.invalidKey) {
            _ = try await responses.heliusClient(keys: keys).send(GetAsset(id: HTTPResponses.keyCheckAsset))
        }
    }

    /// Other failures reach the caller unchanged, so they're never mistaken for a key problem.
    @Test
    func `Other request failures pass through unchanged`() async throws {
        let responses = HTTPResponses.keyCheck(failure: .http(statusCode: 429, retryAfter: nil))
        let keys = SavedKeys()
        try await keys.save("fixture-key")

        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: nil)) {
            _ = try await responses.heliusClient(keys: keys).send(GetAsset(id: HTTPResponses.keyCheckAsset))
        }
    }

    /// Each request reads the saved key, and requests with the same key share one Helius client.
    @Test
    func `Requests use the key saved when they're sent`() async throws {
        let responses = HTTPResponses.keyCheck()
        let keys = SavedKeys()
        let created = Mutex<[String]>([])
        let client = HeliusClient(keys: keys) { key in
            created.withLock { $0.append(key) }
            return HeliusRPC(apiKey: key, network: .mainnet, transport: responses)
        }

        try await keys.save("first-key")
        _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))
        _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))
        try await keys.save("second-key")
        _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))

        #expect(await responses.requests.map { $0.url?.query() } == ["api-key=first-key", "api-key=first-key", "api-key=second-key"])
        #expect(created.withLock(\.self) == ["first-key", "second-key"])
    }
}
