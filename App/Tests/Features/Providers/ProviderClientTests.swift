import Foundation
@testable import Privacy
@testable import RPC
import Synchronization
import Testing
import Transactions
@testable import widgets

/// Checks that requests go to the provider and key saved when they're sent, through the real clients and local HTTP fixtures.
@Suite(.timeLimit(.minutes(1)))
struct ProviderClientTests {
    /// Without a saved key, Helius requests, subscriptions, signature watches, and logo lookups fail before anything
    /// reaches Helius.
    @Test
    func `A missing Helius key fails before contacting Helius`() async {
        let responses = HTTPResponses.keyCheck()
        let client = responses.providerClient(settings: StoredValue(ProviderSettings(selection: .helius)),
                                              providerKey: StoredValue<String>())

        await #expect(throws: ProviderClientError.missingKey) { _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset)) }
        await #expect(throws: ProviderClientError.missingKey) { _ = try await client.changedSlots(for: [PublicWallet.address]) }
        await #expect(throws: ProviderClientError.missingKey) { _ = try await client.events(for: ExternalFixture.signature) }
        await #expect(throws: ProviderClientError.missingKey) { _ = try await client.logos(for: [HTTPResponses.keyCheckAsset]) }
        await #expect(throws: ProviderClientError.missingKey) { _ = try await client.readsPrivateNotes }
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

    /// A signature watch subscribes at the selected provider's devnet host, with Helius's saved key.
    /// - Parameters:
    ///   - provider: The selected provider.
    ///   - host: The provider's devnet host.
    ///   - key: The API key that the connection carries, or `nil` for a provider without one.
    /// - Throws: A test prerequisite error.
    @Test(arguments: [
        (ProviderSettings.Provider.solana, "api.devnet.solana.com", nil),
        (.helius, "devnet.helius-rpc.com", "fixture-key"),
    ] as [(ProviderSettings.Provider, String, String?)])
    func `Signature watches go to the selected provider's devnet host`(provider: ProviderSettings.Provider,
                                                                      host: String, key: String?) async throws {
        let responses = HTTPResponses.keyCheck()
        let sockets = SocketSequence()
        let opened = Mutex<[URL]>([])
        let client = ProviderClient(network: .devnet, settings: StoredValue(ProviderSettings(selection: provider)),
                                    providerKey: StoredValue("fixture-key")) { endpoint, network in
            responses.client(for: endpoint, on: network) { url in
                opened.withLock { $0.append(url) }
                return sockets.connect(url)
            }
        }

        defer { for socket in sockets.sockets { socket.cancel() } }

        _ = try await client.events(for: ExternalFixture.signature)

        let url = try #require(opened.withLock(\.self).first)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(url.host() == host)
        #expect(query.first(where: { $0.name == "api-key" })?.value == key)
        #expect(sockets.sockets.count == 1)
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
        await #expect(throws: ProviderClientError.unsupportedNetwork) { _ = try await client.events(for: ExternalFixture.signature) }
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

    /// Private-note reads go to Helius's indexer on the client's network.
    @Test
    func `Helius reads private notes`() async throws {
        let responses = HTTPResponses.privateNotes()
        let client = responses.providerClient(network: .devnet, settings: StoredValue(ProviderSettings(selection: .helius)),
                                              providerKey: StoredValue("fixture-key"))
        let tag = [UInt8](repeating: 7, count: 32)

        let batch = try await client.shieldedTransactions(taggedWith: [tag], after: nil)
        let spends = try await client.shieldedTransactions(spending: [tag])

        #expect(batch.transactions.isEmpty)
        #expect(spends.isEmpty)
        #expect(try await responses.requests.map { try $0.rpcMethod }.sorted() == [
            GetEncryptedUtxosByTags.method, GetShieldedTransactionsByNullifiers.method, GetShieldedTransactionsByTags.method,
        ])
        #expect(await responses.requests.allSatisfy { $0.url?.host() == "devnet.helius-rpc.com" })
    }

    /// Only Helius reads private notes, and a custom RPC reads nothing off mainnet; the answer sends no request.
    /// - Parameters:
    ///   - provider: The selected provider.
    ///   - network: The client's network.
    ///   - reads: Whether the provider reads private notes there.
    @Test(arguments: [
        (ProviderSettings.Provider.helius, Network.devnet, true), (.helius, .mainnet, true), (.solana, .devnet, false),
        (.custom(URL(string: "https://rpc.example.com")!), .devnet, false),
        (.custom(URL(string: "https://rpc.example.com")!), .mainnet, false),
    ])
    func `Only Helius reads private notes`(provider: ProviderSettings.Provider, network: Network,
                                           reads: Bool) async throws {
        let responses = HTTPResponses.privateNotes()
        let client = responses.providerClient(network: network, settings: StoredValue(ProviderSettings(selection: provider)),
                                              providerKey: StoredValue("fixture-key"))

        #expect(try await client.readsPrivateNotes == reads)
        #expect(await responses.requests.isEmpty)
    }

    /// A provider that doesn't read private notes fails each read before sending anything.
    @Test
    func `Other providers fail private-note reads before sending anything`() async {
        let responses = HTTPResponses.privateNotes()
        let client = responses.providerClient(network: .devnet, settings: StoredValue(ProviderSettings(selection: .solana)),
                                              providerKey: StoredValue<String>())
        let tag = [UInt8](repeating: 7, count: 32)

        await #expect(throws: ProviderClientError.privateNotesUnavailable) {
            _ = try await client.shieldedTransactions(taggedWith: [tag], after: nil)
        }
        await #expect(throws: ProviderClientError.privateNotesUnavailable) {
            _ = try await client.shieldedTransactions(spending: [tag])
        }
        await #expect(throws: ProviderClientError.privateNotesUnavailable) {
            _ = try await client.merkleProofs(for: [tag], inTree: ShieldedPool.tree(id: 1).value)
        }
        await #expect(throws: ProviderClientError.privateNotesUnavailable) {
            _ = try await client.nonInclusionProofs(for: [tag], inTree: ShieldedPool.tree(id: 1).value)
        }
        #expect(await responses.requests.isEmpty)
    }

    /// Tree proof reads go to Helius's indexer on the client's network.
    @Test
    func `Helius reads tree proofs`() async throws {
        let responses = HTTPResponses.privateNotes(prove: PrivateBalanceFixtures.proof(answering:))
        let client = responses.providerClient(network: .devnet, settings: StoredValue(ProviderSettings(selection: .helius)),
                                              providerKey: StoredValue("fixture-key"))
        let tree = try ShieldedPool.tree(id: 1).value
        let leaf = [UInt8](repeating: 7, count: 32)

        async let included = client.merkleProofs(for: [leaf], inTree: tree)
        async let excluded = client.nonInclusionProofs(for: [leaf], inTree: tree)
        let (inclusionProofs, nonInclusionProofs) = try await (included, excluded)

        #expect(inclusionProofs.map(\.leaf) == [leaf])
        #expect(nonInclusionProofs.map(\.nullifier) == [leaf])
        #expect(try await responses.requests.map { try $0.rpcMethod }.sorted() == [GetMerkleProofs.method, GetNonInclusionProofs.method])
        #expect(await responses.requests.allSatisfy { $0.url?.host() == "devnet.helius-rpc.com" })
    }

    /// Proof requests go to Helius's prover route on the client's network.
    @Test
    func `Helius proves private transfers`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let shielded = try await PrivateBalanceFixtures.keys(for: account).shieldedAccount(for: account.address)
        let responses = HTTPResponses.privateNotes(prove: PrivateBalanceFixtures.proof(answering:))
        let client = responses.providerClient(network: .devnet, settings: StoredValue(ProviderSettings(selection: .helius)),
                                              providerKey: StoredValue("fixture-key"))
        let request = try PrivateBalanceFixtures.proofRequest(spending: shielded)

        let proof = try await client.proveTransfer(request)

        let sent = try #require(await responses.requests.first)
        let body = try sent.jsonBody()
        let shape = Shape(inputs: try #require(body["nInputs"] as? Int), outputs: try #require(body["nOutputs"] as? Int))
        #expect(shape == Shape(inputs: 1, outputs: 2))
        #expect(proof.provingKeyDigest == shape.provingKeyDigest)
        #expect(await responses.requests.count == 1)
        #expect(sent.url?.host() == "devnet.helius-rpc.com")
        #expect(sent.url?.path() == "/v1/zolana/prove")
    }

    /// A provider that doesn't prove private transfers, or a custom RPC off mainnet, fails a proof request before
    /// sending anything.
    /// - Parameters:
    ///   - isCustom: Whether a custom RPC is selected instead of Solana's public RPC.
    ///   - error: The error that the proof request throws.
    @Test(arguments: [(false, .privateNotesUnavailable), (true, .unsupportedNetwork)] as [(Bool, ProviderClientError)])
    func `Other providers fail proofs before sending anything`(isCustom: Bool, error: ProviderClientError) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let shielded = try await PrivateBalanceFixtures.keys(for: account).shieldedAccount(for: account.address)
        let responses = HTTPResponses.privateNotes()
        let custom = try #require(URL(string: "https://rpc.example.com"))
        let provider: ProviderSettings.Provider = isCustom ? .custom(custom) : .solana
        let client = responses.providerClient(network: .devnet, settings: StoredValue(ProviderSettings(selection: provider)),
                                              providerKey: StoredValue<String>())
        let request = try PrivateBalanceFixtures.proofRequest(spending: shielded)

        await #expect(throws: error) { _ = try await client.proveTransfer(request) }
        #expect(await responses.requests.isEmpty)
    }

    /// A custom RPC fails private-note reads before sending anything: off mainnet because it serves only mainnet, and
    /// on mainnet because it doesn't read private notes.
    /// - Parameters:
    ///   - network: The client's network.
    ///   - error: The error that each read throws.
    @Test(arguments: [(Network.devnet, ProviderClientError.unsupportedNetwork), (.mainnet, .privateNotesUnavailable)])
    func `A custom RPC fails private-note reads before sending anything`(network: Network,
                                                                         error: ProviderClientError) async throws {
        let responses = HTTPResponses.privateNotes()
        let custom = try #require(URL(string: "https://rpc.example.com"))
        let client = responses.providerClient(network: network, settings: StoredValue(ProviderSettings(selection: .custom(custom))),
                                              providerKey: StoredValue<String>())
        let tag = [UInt8](repeating: 7, count: 32)

        await #expect(throws: error) { _ = try await client.shieldedTransactions(taggedWith: [tag], after: nil) }
        await #expect(throws: error) { _ = try await client.shieldedTransactions(spending: [tag]) }
        #expect(await responses.requests.isEmpty)
    }

    /// Helius rejecting the saved key on a private-note read is reported as a key error.
    /// - Parameter status: The HTTP status Helius returns.
    @Test(arguments: [401, 403])
    func `A rejected Helius key on a private-note read is reported as a key error`(status: Int) async {
        let responses = HTTPResponses.privateNotes(error: .http(statusCode: status, retryAfter: nil))
        let client = responses.providerClient(network: .devnet, settings: StoredValue(ProviderSettings(selection: .helius)),
                                              providerKey: StoredValue("rejected-key"))
        let tag = [UInt8](repeating: 7, count: 32)

        await #expect(throws: ProviderClientError.invalidKey) {
            _ = try await client.shieldedTransactions(taggedWith: [tag], after: nil)
        }
        await #expect(throws: ProviderClientError.invalidKey) { _ = try await client.shieldedTransactions(spending: [tag]) }
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
