import Encoding
import Foundation
import Synchronization
import Testing
import Transactions
@testable import Privacy
@testable import RPC
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ProviderClientTests {
    @Test
    func `A missing Helius key fails before contacting Helius`() async {
        let responses = HTTPResponses.keyCheck()
        let client = responses.providerClient(providers: .inMemory(selection: .helius))

        await #expect(throws: ProviderClientError.missingKey) { _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset)) }
        await #expect(throws: ProviderClientError.missingKey) { _ = try await client.changedSlots(for: [PublicWallet.address]) }
        await #expect(throws: ProviderClientError.missingKey) { _ = try await client.events(for: ExternalFixture.signature) }
        await #expect(throws: ProviderClientError.missingKey) { _ = try await client.logos(for: [HTTPResponses.keyCheckAsset]) }
        await #expect(throws: ProviderClientError.missingKey) { _ = try await client.readsPrivateNotes }
        #expect(await responses.requests.isEmpty)
    }

    @Test(arguments: [401, 403])
    func `A rejected Helius key is reported as a key error`(status: Int) async {
        let responses = HTTPResponses.keyCheck(error: .http(statusCode: status, retryAfter: nil))
        let keys = StoredValue("rejected-key")

        await #expect(throws: ProviderClientError.invalidKey) {
            _ = try await responses.providerClient(
                providers: .inMemory(StoredValue(ProviderSettings(selection: .helius)), key: keys))
                .send(GetAsset(id: HTTPResponses.keyCheckAsset))
        }
    }

    @Test
    func `Other request failures pass through unchanged`() async {
        let responses = HTTPResponses.keyCheck(error: .http(statusCode: 429, retryAfter: nil))
        let keys = StoredValue("fixture-key")

        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: nil)) {
            _ = try await responses.providerClient(
                providers: .inMemory(StoredValue(ProviderSettings(selection: .helius)), key: keys))
                .send(GetAsset(id: HTTPResponses.keyCheckAsset))
        }
    }

    @Test
    func `Each request goes to the provider and key chosen when it's sent`() async throws {
        let responses = HTTPResponses.keyCheck()
        let providers = ProviderStore.inMemory()
        let custom = try #require(URL(string: "https://rpc.example.com/fixture-token"))
        let created = Mutex<[ProviderClient.Endpoint]>([])
        let client = ProviderClient(network: .mainnet, providers: providers) { endpoint, network in
            created.withLock { $0.append(endpoint) }
            return responses.client(for: endpoint, on: network)
        }

        _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))
        _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))
        try await providers.add(custom)
        _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))
        try await providers.save(key: "first-key")
        try await providers.select(.helius)
        _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))
        try await providers.save(key: "second-key")
        _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))

        #expect(await responses.requests.map { $0.url?.host() } == [
            "api.mainnet.solana.com", "api.mainnet.solana.com", "rpc.example.com", "mainnet.helius-rpc.com", "mainnet.helius-rpc.com",
        ])
        #expect(created.withLock(\.self) == [.solana, .custom(custom), .helius(key: "first-key"), .helius(key: "second-key")])
    }

    @Test(arguments: [
        (ProviderSettings.Provider.solana, "api.devnet.solana.com", nil),
        (.helius, "devnet.helius-rpc.com", "fixture-key"),
    ] as [(ProviderSettings.Provider, String, String?)])
    func `Devnet requests go to each provider's devnet host`(provider: ProviderSettings.Provider, host: String,
                                                             key: String?) async throws {
        let responses = HTTPResponses.keyCheck()
        let settings = StoredValue(ProviderSettings(selection: provider))
        let client = responses.providerClient(network: .devnet,
                                              providers: .inMemory(settings, key: StoredValue("fixture-key")))

        _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))

        let url = try #require(await responses.requests.first?.url)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(url.host() == host)
        #expect(query.first(where: { $0.name == "api-key" })?.value == key)
    }

    @Test(arguments: [
        (ProviderSettings.Provider.solana, "api.devnet.solana.com", nil),
        (.helius, "devnet.helius-rpc.com", "fixture-key"),
    ] as [(ProviderSettings.Provider, String, String?)])
    func `Signature watches go to the selected provider's devnet host`(provider: ProviderSettings.Provider,
                                                                      host: String, key: String?) async throws {
        let responses = HTTPResponses.keyCheck()
        let sockets = SocketSequence()
        let opened = Mutex<[URL]>([])
        let providers = ProviderStore.inMemory(selection: provider, key: "fixture-key")
        let client = ProviderClient(network: .devnet, providers: providers) { endpoint, network in
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

    @Test
    func `A custom RPC fails on devnet before contacting it`() async throws {
        let responses = HTTPResponses.keyCheck()
        let custom = try #require(URL(string: "https://rpc.example.com"))
        let settings = StoredValue(ProviderSettings(selection: .custom(custom)))
        let client = responses.providerClient(network: .devnet, providers: .inMemory(settings))
        let asset = HTTPResponses.keyCheckAsset

        await #expect(throws: ProviderClientError.unsupportedNetwork) { _ = try await client.send(GetAsset(id: asset)) }
        await #expect(throws: ProviderClientError.unsupportedNetwork) { _ = try await client.changedSlots(for: [PublicWallet.address]) }
        await #expect(throws: ProviderClientError.unsupportedNetwork) { _ = try await client.events(for: ExternalFixture.signature) }
        await #expect(throws: ProviderClientError.unsupportedNetwork) { _ = try await client.logos(for: [asset]) }
        #expect(await responses.requests.isEmpty)
    }

    @Test(arguments: [ProviderSettings.Provider.solana, .custom(URL(string: "https://rpc.example.com")!)])
    func `Only Helius reports key errors`(provider: ProviderSettings.Provider) async throws {
        let responses = HTTPResponses.keyCheck(error: .http(statusCode: 401, retryAfter: nil))
        let client = responses.providerClient(providers: .inMemory(selection: provider))

        await #expect(throws: RPCError.http(statusCode: 401, retryAfter: nil)) {
            _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))
        }
    }

    @Test(arguments: [(ProviderSettings.Provider.helius, 1), (.solana, 0)])
    func `Only a provider with logo copies looks up logos`(provider: ProviderSettings.Provider, lookups: Int) async throws {
        let responses = HTTPResponses(["getAssetBatch": ["[null]"]])
        let keys = StoredValue("fixture-key")
        let client = responses.providerClient(
            providers: .inMemory(StoredValue(ProviderSettings(selection: provider)), key: keys))

        #expect(try await client.logos(for: [HTTPResponses.keyCheckAsset]).isEmpty)
        #expect(await responses.requests.count == lookups)
    }

    @Test(arguments: [
        (ProviderSettings.Provider.solana, Network.devnet), (.helius, .devnet),
        (.custom(URL(string: "https://rpc.example.com")!), .mainnet),
    ])
    func `Every usable provider reads private notes and proves private transfers without sending its key`(
        provider: ProviderSettings.Provider, network: Network
    ) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let shielded = try await PrivateBalanceFixtures.keys(for: account).shieldedAccount(for: account.address)
        let responses = HTTPResponses.privateNotes(prover: try IndexedProofs.prover(), respond: Self.merkleProofs(answering:))
        let client = responses.providerClient(network: network,
                                              providers: .inMemory(selection: provider, key: "fixture-key"))
        let tag = [UInt8](repeating: 7, count: 32)
        let request = try PrivateBalanceFixtures.proofRequest(spending: shielded)

        async let tagged = client.shieldedTransactions(taggedWith: [tag], after: nil)
        async let spending = client.shieldedTransactions(spending: [tag])
        async let included = client.merkleProofs(for: [tag], inTree: try ShieldedPool.tree(id: 1).value)
        async let proved = client.proveTransfer(request)
        let (batch, spends, inclusionProofs, proof) = try await (tagged, spending, included, proved)

        #expect(batch.transactions.isEmpty)
        #expect(spends.isEmpty)
        #expect(inclusionProofs.map(\.leaf) == [tag])
        #expect(proof.proof.provingKeyDigest == Shape(inputs: 1, outputs: 2).provingKeyDigest)
        #expect(proof.resolution.trees.map(\.id) == [1])
        let reads = await responses.requests.filter {
            $0.httpMethod == "POST" && $0.url?.path().hasSuffix("/indexed") != true
        }
        #expect(try reads.map { try $0.rpcMethod }.sorted() == [
            GetEncryptedUtxosByTags.method, GetMerkleProofs.method, GetShieldedTransactionsByNullifiers.method,
            GetShieldedTransactionsByTags.method,
        ])
        #expect(await PrivateBalanceFixtures.proofRequests(of: responses) == 1)
        #expect(await responses.requests.allSatisfy { $0.url?.query()?.contains("api-key") != true })
    }

    @Test(arguments: [
        (ProviderSettings.Provider.custom(URL(string: "https://rpc.example.com")!), Network.devnet,
         ProviderClientError.unsupportedNetwork),
        (.helius, .devnet, .missingKey),
        (.custom(URL(string: "http://rpc.example.com")!), .mainnet, .unusableEndpoint),
    ])
    func `Private-note reads and proofs fail before sending anything when the selected provider can't be used`(
        provider: ProviderSettings.Provider, network: Network, error: ProviderClientError
    ) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let shielded = try await PrivateBalanceFixtures.keys(for: account).shieldedAccount(for: account.address)
        let responses = HTTPResponses.privateNotes(prover: try IndexedProofs.prover())
        let client = responses.providerClient(network: network, providers: .inMemory(selection: provider))
        let tag = [UInt8](repeating: 7, count: 32)
        let request = try PrivateBalanceFixtures.proofRequest(spending: shielded)

        await #expect(throws: error) { _ = try await client.shieldedTransactions(taggedWith: [tag], after: nil) }
        await #expect(throws: error) { _ = try await client.shieldedTransactions(spending: [tag]) }
        await #expect(throws: error) { _ = try await client.merkleProofs(for: [tag], inTree: try ShieldedPool.tree(id: 1).value) }
        await #expect(throws: error) { _ = try await client.proveTransfer(request) }
        #expect(await responses.requests.isEmpty)
    }

    @Test(arguments: [
        (ProviderSettings.Provider.solana, Network.devnet, true), (.solana, .mainnet, true),
        (.helius, .devnet, true), (.helius, .mainnet, true),
        (.custom(URL(string: "https://rpc.example.com")!), .devnet, false),
        (.custom(URL(string: "https://rpc.example.com")!), .mainnet, true),
    ])
    func `Private notes read wherever the selected provider serves the network`(provider: ProviderSettings.Provider,
                                                                              network: Network,
                                                                              reads: Bool) async throws {
        let responses = HTTPResponses.privateNotes()
        let client = responses.providerClient(network: network,
                                              providers: .inMemory(selection: provider, key: "fixture-key"))

        #expect(try await client.readsPrivateNotes == reads)
        #expect(await responses.requests.isEmpty)
    }

    @Test
    func `One Solana Rings provider serves every provider and key`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let shielded = try await PrivateBalanceFixtures.keys(for: account).shieldedAccount(for: account.address)
        let responses = HTTPResponses.privateNotes(prover: try IndexedProofs.prover())
        let providers = ProviderStore.inMemory(selection: .solana)
        let client = responses.providerClient(network: .devnet, providers: providers)
        let request = try PrivateBalanceFixtures.proofRequest(spending: shielded)

        _ = try await client.proveTransfer(request)
        try await providers.save(key: "first-key")
        try await providers.select(.helius)
        _ = try await client.proveTransfer(request)
        try await providers.save(key: "second-key")
        _ = try await client.proveTransfer(request)

        #expect(await PrivateBalanceFixtures.proofRequests(of: responses) == 3)
        #expect(await responses.requests.count { $0.url?.path().hasSuffix("/tee/v1/attestation") == true } == 1)
    }

    @Test(arguments: [401, 403])
    func `A Solana Rings rejection with Helius selected isn't reported as a key error`(status: Int) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let shielded = try await PrivateBalanceFixtures.keys(for: account).shieldedAccount(for: account.address)
        let responses = HTTPResponses.privateNotes(error: .http(statusCode: status, retryAfter: nil)) { _ in "" }
        let client = responses.providerClient(network: .devnet,
                                              providers: .inMemory(selection: .helius, key: "rejected-key"))
        let tag = [UInt8](repeating: 7, count: 32)
        let request = try PrivateBalanceFixtures.proofRequest(spending: shielded)
        let rejection = RPCError.http(statusCode: status, retryAfter: nil)

        await #expect(throws: rejection) { _ = try await client.shieldedTransactions(taggedWith: [tag], after: nil) }
        await #expect(throws: rejection) { _ = try await client.shieldedTransactions(spending: [tag]) }
        await #expect(throws: rejection) { _ = try await client.proveTransfer(request) }
    }

    @Test
    func `A saved custom URL that isn't HTTPS can't be used`() async throws {
        let responses = HTTPResponses.keyCheck()
        let insecure = try #require(URL(string: "http://rpc.example.com"))
        let client = responses.providerClient(providers: .inMemory(selection: .custom(insecure)))

        await #expect(throws: ProviderClientError.unusableEndpoint) {
            _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))
        }
        #expect(await responses.requests.isEmpty)
    }

    nonisolated private static func merkleProofs(answering request: URLRequest) throws -> String {
        let params = try #require(try request.jsonBody()["params"] as? [String: Any])
        let tree = try #require(params["treeAccount"] as? String)
        let zero = Base58.encode([UInt8](repeating: 0, count: 32))
        let proofs = try #require(params["leaves"] as? [String]).map { leaf in
            MerkleProofReplies.proof(leaf: leaf, tree: tree, path: Array(repeating: zero, count: 32), leafIndex: 0, root: zero,
                                     rootIndex: 0)
        }
        return MerkleProofReplies.result(proofs)
    }
}
