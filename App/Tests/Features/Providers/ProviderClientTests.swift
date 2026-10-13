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
        let client = responses.providerClient(settings: StoredValue(ProviderSettings(selection: .helius)),
                                              providerKey: StoredValue<String>())

        await #expect(throws: ProviderClientError.missingKey) { _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset)) }
        await #expect(throws: ProviderClientError.missingKey) { _ = try await client.changedSlots(for: [PublicWallet.address]) }
        await #expect(throws: ProviderClientError.missingKey) { _ = try await client.logos(for: [HTTPResponses.keyCheckAsset]) }
        #expect(await responses.requests.isEmpty)
    }

    /// Helius rejecting the saved key is reported as a typed error, never as a generic HTTP error.
    /// - Parameter status: The HTTP status Helius returns.
    @Test(arguments: [401, 403])
    func `A rejected Helius key is reported as a key error`(status: Int) async {
        let responses = HTTPResponses.keyCheck(error: .http(statusCode: status, retryAfter: nil))
        let keys = StoredValue("rejected-key")

        await #expect(throws: ProviderClientError.invalidKey) {
            _ = try await responses.providerClient(settings: StoredValue(ProviderSettings(selection: .helius)), providerKey: keys)
                .send(GetAsset(id: HTTPResponses.keyCheckAsset))
        }
    }

    /// Other failures reach the caller unchanged, so they're never mistaken for a key problem.
    @Test
    func `Other request failures pass through unchanged`() async {
        let responses = HTTPResponses.keyCheck(error: .http(statusCode: 429, retryAfter: nil))
        let keys = StoredValue("fixture-key")

        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: nil)) {
            _ = try await responses.providerClient(settings: StoredValue(ProviderSettings(selection: .helius)), providerKey: keys)
                .send(GetAsset(id: HTTPResponses.keyCheckAsset))
        }
    }

    /// Each request reads the saved choice and key, starting at Solana's public RPC before anything is saved, and
    /// requests to the same endpoint share one client.
    @Test
    func `Each request goes to the provider and key saved when it's sent`() async throws {
        let responses = HTTPResponses.keyCheck()
        let settings = StoredValue<ProviderSettings>()
        let keys = StoredValue<String>()
        let custom = try #require(URL(string: "https://rpc.example.com/fixture-token"))
        let created = Mutex<[ProviderClient.Endpoint]>([])
        let client = ProviderClient(network: .mainnet, settings: settings, providerKey: keys) { endpoint, network in
            created.withLock { $0.append(endpoint) }
            return responses.client(for: endpoint, on: network)
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

    /// On devnet, Solana's public RPC and Helius each serve requests at their own devnet host, Helius with the same
    /// saved key.
    /// - Parameters:
    ///   - provider: A built-in provider.
    ///   - host: The provider's devnet host.
    ///   - key: The API key that the request carries, or `nil` for a provider without one.
    /// - Throws: A test prerequisite error.
    @Test(arguments: [
        (ProviderSettings.Provider.solana, "api.devnet.solana.com", nil),
        (.helius, "devnet.helius-rpc.com", "fixture-key"),
    ] as [(ProviderSettings.Provider, String, String?)])
    func `Devnet requests go to each provider's devnet host`(provider: ProviderSettings.Provider, host: String,
                                                             key: String?) async throws {
        let responses = HTTPResponses.keyCheck()
        let settings = StoredValue(ProviderSettings(selection: provider))
        let client = responses.providerClient(network: .devnet, settings: settings, providerKey: StoredValue("fixture-key"))

        _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))

        let url = try #require(await responses.requests.first?.url)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(url.host() == host)
        #expect(query.first(where: { $0.name == "api-key" })?.value == key)
    }

    /// On devnet, a selected custom RPC fails before anything is sent, instead of using another provider, because
    /// custom RPCs serve mainnet.
    /// - Throws: A test prerequisite error.
    @Test
    func `A custom RPC fails on devnet before contacting it`() async throws {
        let responses = HTTPResponses.keyCheck()
        let custom = try #require(URL(string: "https://rpc.example.com"))
        let settings = StoredValue(ProviderSettings(selection: .custom(custom)))
        let client = responses.providerClient(network: .devnet, settings: settings, providerKey: StoredValue<String>())
        let asset = HTTPResponses.keyCheckAsset

        await #expect(throws: ProviderClientError.unsupportedNetwork) { _ = try await client.send(GetAsset(id: asset)) }
        await #expect(throws: ProviderClientError.unsupportedNetwork) { _ = try await client.changedSlots(for: [PublicWallet.address]) }
        await #expect(throws: ProviderClientError.unsupportedNetwork) { _ = try await client.logos(for: [asset]) }
        #expect(await responses.requests.isEmpty)
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
        let keys = StoredValue("fixture-key")
        let client = responses.providerClient(settings: StoredValue(ProviderSettings(selection: provider)), providerKey: keys)

        #expect(try await client.logos(for: [HTTPResponses.keyCheckAsset]).isEmpty)
        #expect(await responses.requests.count == lookups)
    }

    /// Each endpoint gets its production client for the network, and a custom URL that isn't HTTPS gets none.
    /// - Parameters:
    ///   - endpoint: A saved endpoint.
    ///   - network: The network that receives the client's requests.
    ///   - description: The created client's description, or `nil` when no client can be created.
    @Test(arguments: [
        (ProviderClient.Endpoint.solana, Network.mainnet, "Solana(mainnet)"),
        (.solana, .devnet, "Solana(devnet)"),
        (.helius(key: "fixture-key"), .mainnet, "HeliusRPC(mainnet)"),
        (.helius(key: "fixture-key"), .devnet, "HeliusRPC(devnet)"),
        (.custom(URL(string: "https://rpc.example.com")!), .mainnet, "Solana(mainnet)"),
        (.custom(URL(string: "http://rpc.example.com")!), .mainnet, nil),
    ] as [(ProviderClient.Endpoint, Network, String?)])
    func `Each endpoint gets its production client for the network`(endpoint: ProviderClient.Endpoint, network: Network,
                                                                    description: String?) {
        #expect(ProviderClient.client(for: endpoint, on: network).map { String(describing: $0) } == description)
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
