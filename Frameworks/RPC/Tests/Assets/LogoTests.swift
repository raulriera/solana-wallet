import Foundation
import Testing
@testable import RPC

struct LogoTests {
    private static let logoCopy = #"""
        "result":[{"id":"mint","content":{"files":[{"cdn_uri":"https://example.com/a.png","mime":"image/png"}]}}]
        """#

    @Test
    func `Logos come from one batch request and only from the provider's copies`() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #"""
                "result":[
                  {"id":"with-logo","interface":"FungibleToken","content":{"files":[
                    {"uri":"https://creator.example/logo.png","cdn_uri":"https://cdn.example.com/logo.png","mime":"image/png"}]}},
                  null,
                  {"id":"creator-only","interface":"FungibleToken","content":{"files":[
                    {"uri":"https://creator.example/other.png","mime":"image/png"}]}},
                  {"id":"no-image","interface":"FungibleToken"},
                  {"id":"unrequested","interface":"FungibleToken","content":{"files":[
                    {"cdn_uri":"https://cdn.example.com/unrequested.png","mime":"image/png"}]}}
                ]
                """#)
        }
        let provider: any LogoProviding = HeliusRPC(apiKey: "fixture-key", network: .mainnet, transport: transport)
        let logo = try #require(URL(string: "https://cdn.example.com/logo.png"))

        let logos = try await provider.logos(for: ["with-logo", "unknown", "creator-only", "no-image", "with-logo"])

        #expect(logos == ["with-logo": logo])
        let requests = await transport.requests
        #expect(requests.count == 1)
        let body = try requestBody(try #require(requests.first))
        #expect(body["method"] as? String == "getAssetBatch")
        let parameters = try #require(body["params"] as? [String: Any])
        #expect(parameters["ids"] as? [String] == ["with-logo", "unknown", "creator-only", "no-image"])
    }

    @Test
    func `Empty logo lookups do not access the network`() async throws {
        let transport = StubTransport { try reply(to: $0, payload: #""result":[]"#) }
        #expect(try await HeliusRPC(apiKey: "fixture-key", network: .mainnet, transport: transport).logos(for: []).isEmpty)
        #expect(await transport.requests.isEmpty)
    }

    @Test(arguments: [(Capabilities(), 0), (.logos, 1)])
    func `A custom endpoint looks up logos only when it declares the capability`(
        capabilities: Capabilities,
        requests: Int
    ) async throws {
        let transport = StubTransport { try reply(to: $0, payload: #""result":[]"#) }
        let provider = try customProvider(transport: transport, capabilities: capabilities)
        #expect(try await provider.logos(for: ["mint"]).isEmpty)
        #expect(await transport.requests.count == requests)
    }

    @Test(arguments: [
        (logoCopy, true),
        (#""result":[null]"#, false),
        (#""error":{"code":-32601,"message":"Method not found"}"#, false),
    ])
    func `The logo check reports a server that returns the mint's logo copy, whatever the client declares`(
        payload: String,
        serves: Bool
    ) async throws {
        let transport = StubTransport { try reply(to: $0, payload: payload) }
        let provider = try customProvider(transport: transport)

        #expect(try await provider.servesLogos(checking: "mint") == serves)
        #expect(await transport.requests.count == 1)
    }

    @Test
    func `A rate-limited logo check fails`() async throws {
        let transport = StubTransport { try reply(to: $0, payload: #""result":[]"#, status: 429) }
        let provider = try customProvider(transport: transport)

        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: nil)) {
            try await provider.servesLogos(checking: "mint")
        }
    }

    @Test
    func `A cancelled logo check fails with a cancellation`() async throws {
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (pending, release) = AsyncStream<Void>.makeStream()
        defer { startedContinuation.finish(); release.finish() }
        let transport = StubTransport { request in
            startedContinuation.yield(())
            for await _ in pending {}
            try Task.checkCancellation()
            return try reply(to: request, payload: #""result":[]"#)
        }
        let provider = try customProvider(transport: transport)
        let check = Task { try await provider.servesLogos(checking: "mint") }
        defer { check.cancel() }
        var iterator = started.makeAsyncIterator()
        _ = try #require(await iterator.next())

        check.cancel()

        await #expect(throws: CancellationError.self) { try await check.value }
    }

    @Test
    func `Lookups of more than fifty mints fail without accessing the network`() async {
        let transport = StubTransport { try reply(to: $0, payload: #""result":[]"#) }
        let mints = (0...50).map { "mint-\($0)" }
        await #expect(throws: LogoError.tooManyMints) {
            try await HeliusRPC(apiKey: "fixture-key", network: .mainnet, transport: transport).logos(for: mints)
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test
    func `A malformed asset fails the lookup`() async {
        let transport = StubTransport {
            try reply(to: $0, payload: #""result":[{"id":false,"interface":"FungibleToken"}]"#)
        }
        await #expect(throws: RPCError.decoding) {
            try await HeliusRPC(apiKey: "fixture-key", network: .mainnet, transport: transport).logos(for: ["mint"])
        }
    }

    private func customProvider(transport: StubTransport, capabilities: Capabilities = []) throws -> SolanaRPC {
        let endpoint = try #require(URL(string: "https://rpc.example.com"))
        return try #require(
            SolanaRPC(endpoint: endpoint, network: .mainnet, capabilities: capabilities, transport: transport)
        )
    }
}
