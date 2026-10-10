import Foundation
@testable import RPC
import Synchronization
import Testing
@testable import widgets

/// Checks that requests go to the provider and key saved when they're sent, through the real clients and local HTTP fixtures.
@Suite(.timeLimit(.minutes(1)))
struct ProviderClientTests {
    /// Without a saved key, Helius requests, subscriptions, and logo lookups fail before anything reaches Helius.
    @Test
    func `A missing Helius key fails before contacting Helius`() async {
        let responses = HTTPResponses.keyCheck()
        let client = responses.providerClient(settings: StoredValue<ProviderSettings>(), providerKey: StoredValue<String>())

        await #expect(throws: ProviderClientError.missingKey) { _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset)) }
        await #expect(throws: ProviderClientError.missingKey) { _ = try await client.changedSlots(for: [PublicWallet.address]) }
        await #expect(throws: ProviderClientError.missingKey) { _ = try await client.logos(for: [HTTPResponses.keyCheckAsset]) }
        #expect(await responses.requests.isEmpty)
    }

    /// Helius rejecting the saved key is reported as a typed error, never as a generic HTTP error.
    /// - Parameter status: The HTTP status Helius returns.
    @Test(arguments: [401, 403])
    func `A rejected Helius key is reported as a key error`(status: Int) async throws {
        let responses = HTTPResponses.keyCheck(error: .http(statusCode: status, retryAfter: nil))
        let keys = StoredValue<String>()
        try await keys.save("rejected-key")

        await #expect(throws: ProviderClientError.invalidKey) {
            _ = try await responses.providerClient(settings: StoredValue<ProviderSettings>(), providerKey: keys).send(GetAsset(id: HTTPResponses.keyCheckAsset))
        }
    }

    /// Other failures reach the caller unchanged, so they're never mistaken for a key problem.
    @Test
    func `Other request failures pass through unchanged`() async throws {
        let responses = HTTPResponses.keyCheck(error: .http(statusCode: 429, retryAfter: nil))
        let keys = StoredValue<String>()
        try await keys.save("fixture-key")

        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: nil)) {
            _ = try await responses.providerClient(settings: StoredValue<ProviderSettings>(), providerKey: keys).send(GetAsset(id: HTTPResponses.keyCheckAsset))
        }
    }

    /// Each request reads the saved choice and key, and requests to the same endpoint share one client.
    @Test
    func `Each request goes to the provider and key saved when it's sent`() async throws {
        let responses = HTTPResponses.keyCheck()
        let settings = StoredValue(ProviderSettings(selection: .solana))
        let keys = StoredValue<String>()
        let custom = try #require(URL(string: "https://rpc.example.com/fixture-token"))
        let created = Mutex<[ProviderClient.Endpoint]>([])
        let client = ProviderClient(settings: settings, providerKey: keys) { endpoint in
            created.withLock { $0.append(endpoint) }
            return responses.client(for: endpoint)
        }

        _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))
        _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))
        try await settings.save(ProviderSettings(selection: .custom(custom)))
        _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))
        try await keys.save("first-key")
        try await settings.save(ProviderSettings(selection: .helius))
        _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))
        try await keys.save("second-key")
        _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))

        #expect(await responses.requests.map { $0.url?.host() } == [
            "api.mainnet.solana.com", "api.mainnet.solana.com", "rpc.example.com", "mainnet.helius-rpc.com", "mainnet.helius-rpc.com",
        ])
        #expect(created.withLock(\.self) == [.solana, .custom(custom), .helius(key: "first-key"), .helius(key: "second-key")])
    }

    /// Providers other than Helius need no key and pass their own rejections through unchanged.
    /// - Parameter provider: A provider without an API key.
    @Test(arguments: [ProviderSettings.Provider.solana, .custom(URL(string: "https://rpc.example.com")!)])
    func `Only Helius reports key errors`(provider: ProviderSettings.Provider) async throws {
        let responses = HTTPResponses.keyCheck(error: .http(statusCode: 401, retryAfter: nil))
        let client = responses.providerClient(settings: StoredValue(ProviderSettings(selection: provider)),
                                              providerKey: StoredValue<String>())

        await #expect(throws: RPCError.http(statusCode: 401, retryAfter: nil)) {
            _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))
        }
    }

    /// Only a provider with logo copies is asked for logos; another provider gives none without a request.
    /// - Parameters:
    ///   - provider: The selected provider.
    ///   - lookups: The number of logo requests expected.
    @Test(arguments: [(ProviderSettings.Provider.helius, 1), (.solana, 0)])
    func `Only a provider with logo copies looks up logos`(provider: ProviderSettings.Provider, lookups: Int) async throws {
        let responses = HTTPResponses(["getAssetBatch": ["[null]"]])
        let keys = StoredValue<String>()
        try await keys.save("fixture-key")
        let client = responses.providerClient(settings: StoredValue(ProviderSettings(selection: provider)), providerKey: keys)

        #expect(try await client.logos(for: [HTTPResponses.keyCheckAsset]).isEmpty)
        #expect(await responses.requests.count == lookups)
    }

    /// Each endpoint gets its production client, and a custom URL that isn't HTTPS gets none.
    /// - Parameters:
    ///   - endpoint: A saved endpoint.
    ///   - description: The created client's description, or `nil` when no client can be created.
    @Test(arguments: [
        (ProviderClient.Endpoint.solana, "Solana(mainnet)"),
        (.helius(key: "fixture-key"), "HeliusRPC(mainnet)"),
        (.custom(URL(string: "https://rpc.example.com")!), "Solana(mainnet)"),
        (.custom(URL(string: "http://rpc.example.com")!), nil),
    ] as [(ProviderClient.Endpoint, String?)])
    func `Each endpoint gets its production client`(endpoint: ProviderClient.Endpoint, description: String?) {
        #expect(ProviderClient.mainnetClient(for: endpoint).map { String(describing: $0) } == description)
    }

    /// A saved custom URL that the client can't use fails without sending a request.
    @Test
    func `A saved custom URL that isn't HTTPS can't be used`() async throws {
        let responses = HTTPResponses.keyCheck()
        let insecure = try #require(URL(string: "http://rpc.example.com"))
        let client = responses.providerClient(settings: StoredValue(ProviderSettings(selection: .custom(insecure))),
                                              providerKey: StoredValue<String>())

        await #expect(throws: ProviderClientError.unusableEndpoint) {
            _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))
        }
        #expect(await responses.requests.isEmpty)
    }
}
