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
struct SelectedRPCProviderTests {
    @Test
    func `A missing Helius key fails before contacting Helius`() async {
        let responses = HTTPResponses.keyCheck()
        let client = responses.rpcProvider(rpcStore: .inMemory(selection: .helius))

        await #expect(throws: RPCProviderError.missingKey) { _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset)) }
        await #expect(throws: RPCProviderError.missingKey) { _ = try await client.changedSlots(for: [PublicWallet.address]) }
        await #expect(throws: RPCProviderError.missingKey) { _ = try await client.events(for: ExternalFixture.signature) }
        await #expect(throws: RPCProviderError.missingKey) { _ = try await client.logos(for: [HTTPResponses.keyCheckAsset]) }
        #expect(await responses.requests.isEmpty)
    }

    @Test
    func `A rejected Helius key is reported as a key error`() async {
        let responses = HTTPResponses.keyCheck(error: .http(statusCode: 401, retryAfter: nil))
        let keys = StoredValue("rejected-key")

        await #expect(throws: RPCProviderError.invalidKey) {
            _ = try await responses.rpcProvider(
                rpcStore: .inMemory(StoredValue(RPCSettings(selection: .helius)), key: keys))
                .send(GetAsset(id: HTTPResponses.keyCheckAsset))
        }
    }

    @Test
    func `Other request failures pass through unchanged`() async {
        let responses = HTTPResponses.keyCheck(error: .http(statusCode: 429, retryAfter: nil))
        let keys = StoredValue("fixture-key")

        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: nil)) {
            _ = try await responses.rpcProvider(
                rpcStore: .inMemory(StoredValue(RPCSettings(selection: .helius)), key: keys))
                .send(GetAsset(id: HTTPResponses.keyCheckAsset))
        }
    }

    @Test
    func `Each request goes to the provider and key chosen when it's sent`() async throws {
        let responses = HTTPResponses.keyCheck()
        let rpcStore = RPCStore.inMemory()
        let custom = try #require(URL(string: "https://rpc.example.com/fixture-token"))
        let created = Mutex<[SelectedRPCProvider.Endpoint]>([])
        let client = SelectedRPCProvider(network: .mainnet, rpcStore: rpcStore) { endpoint, network in
            created.withLock { $0.append(endpoint) }
            return responses.client(for: endpoint, on: network)
        }

        _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))
        _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))
        try await rpcStore.add(custom, capabilities: [])
        _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))
        try await rpcStore.save(key: "first-key")
        try await rpcStore.select(.helius)
        _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))
        try await rpcStore.save(key: "second-key")
        _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))

        #expect(await responses.requests.map { $0.url?.host() } == [
            "api.mainnet.solana.com", "api.mainnet.solana.com", "rpc.example.com", "mainnet.helius-rpc.com", "mainnet.helius-rpc.com",
        ])
        #expect(created.withLock(\.self) == [
            .solana, .custom(custom, capabilities: []), .helius(key: "first-key"), .helius(key: "second-key"),
        ])
    }

    @Test(arguments: [
        (RPCSettings.Provider.solana, "api.devnet.solana.com", nil),
        (.helius, "devnet.helius-rpc.com", "fixture-key"),
    ] as [(RPCSettings.Provider, String, String?)])
    func `Devnet requests go to each provider's devnet host`(provider: RPCSettings.Provider, host: String,
                                                             key: String?) async throws {
        let responses = HTTPResponses.keyCheck()
        let settings = StoredValue(RPCSettings(selection: provider))
        let client = responses.rpcProvider(network: .devnet,
                                           rpcStore: .inMemory(settings, key: StoredValue("fixture-key")))

        _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))

        let url = try #require(await responses.requests.first?.url)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(url.host() == host)
        #expect(query.first(where: { $0.name == "api-key" })?.value == key)
    }

    @Test
    func `A custom RPC fails on devnet before contacting it`() async throws {
        let responses = HTTPResponses.keyCheck()
        let custom = try #require(URL(string: "https://rpc.example.com"))
        let settings = StoredValue(RPCSettings(selection: .custom(custom), customRPCs: [custom]))
        let client = responses.rpcProvider(network: .devnet, rpcStore: .inMemory(settings))
        let asset = HTTPResponses.keyCheckAsset

        await #expect(throws: RPCProviderError.unsupportedNetwork) { _ = try await client.send(GetAsset(id: asset)) }
        await #expect(throws: RPCProviderError.unsupportedNetwork) { _ = try await client.changedSlots(for: [PublicWallet.address]) }
        await #expect(throws: RPCProviderError.unsupportedNetwork) { _ = try await client.events(for: ExternalFixture.signature) }
        await #expect(throws: RPCProviderError.unsupportedNetwork) { _ = try await client.logos(for: [asset]) }
        #expect(try await client.capabilities.isEmpty)
        #expect(await responses.requests.isEmpty)
    }

    @Test
    func `Only Helius reports key errors`() async throws {
        let responses = HTTPResponses.keyCheck(error: .http(statusCode: 401, retryAfter: nil))
        let client = responses.rpcProvider(rpcStore: .inMemory(selection: .solana))

        await #expect(throws: RPCError.http(statusCode: 401, retryAfter: nil)) {
            _ = try await client.send(GetAsset(id: HTTPResponses.keyCheckAsset))
        }
    }

    @Test(arguments: [
        (RPCSettings.Provider.helius, true), (.solana, false),
        (.custom(URL(string: "https://rpc.example.com")!), false),
    ])
    func `Only a provider that declares private balances serves them`(provider: RPCSettings.Provider,
                                                                   serves: Bool) async throws {
        let responses = HTTPResponses.keyCheck()
        let client = responses.rpcProvider(rpcStore: .inMemory(selection: provider, key: "fixture-key"))

        #expect(try await client.capabilities.contains(.privateBalances) == serves)
        #expect(await responses.requests.isEmpty)
    }

    @Test
    func `Helius reads private notes and proves private transfers with its key`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let shielded = try await PrivateBalanceFixtures.keys(for: account).shieldedAccount(for: account.address)
        let responses = HTTPResponses.privateNotes(prover: try IndexedProofs.prover(), respond: Self.merkleProofs(answering:))
        let client = responses.rpcProvider(network: .mainnet,
                                           rpcStore: .inMemory(selection: .helius, key: "fixture-key"))
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
        #expect(await responses.requests.allSatisfy { $0.url?.query()?.contains("api-key=fixture-key") == true })
    }

    @Test
    func `A custom RPC declares the capabilities it was saved with`() async throws {
        let custom = try #require(URL(string: "https://rpc.example.com"))
        let saved = RPCSettings.CustomRPC(url: custom, capabilities: .privateBalances)
        let rpcStore = RPCStore.inMemory(StoredValue(RPCSettings(selection: .custom(custom), customRPCs: [saved])))

        #expect(try await SelectedRPCProvider(network: .mainnet, rpcStore: rpcStore).capabilities == .privateBalances)
    }

    @Test
    func `A key change proves with a new client that has the new key and its own attestation`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let shielded = try await PrivateBalanceFixtures.keys(for: account).shieldedAccount(for: account.address)
        let responses = HTTPResponses.privateNotes(prover: try IndexedProofs.prover())
        let rpcStore = RPCStore.inMemory(selection: .helius, key: "first-key")
        let client = responses.rpcProvider(network: .devnet, rpcStore: rpcStore)
        let request = try PrivateBalanceFixtures.proofRequest(spending: shielded)

        _ = try await client.proveTransfer(request)
        _ = try await client.proveTransfer(request)
        try await rpcStore.save(key: "second-key")
        _ = try await client.proveTransfer(request)

        let urls = await responses.requests.compactMap(\.url)
        let attestations = urls.filter { $0.path().hasSuffix("/attestation") }
        #expect(attestations.map { $0.query()?.hasPrefix("api-key=first-key") } == [true, false])
        #expect(urls.last?.query() == "api-key=second-key")
        #expect(await PrivateBalanceFixtures.proofRequests(of: responses) == 3)
    }

    @Test
    func `A saved custom URL that isn't HTTPS can't be used`() async throws {
        let responses = HTTPResponses.keyCheck()
        let insecure = try #require(URL(string: "http://rpc.example.com"))
        let client = responses.rpcProvider(rpcStore: .inMemory(selection: .custom(insecure)))

        await #expect(throws: RPCProviderError.unusableEndpoint) {
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
