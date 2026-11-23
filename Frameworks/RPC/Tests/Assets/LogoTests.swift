import Foundation
import Testing
@testable import RPC

struct LogoTests {
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
        #expect(try requestedIDs(try #require(requests.first)) == ["with-logo", "unknown", "creator-only", "no-image"])
    }

    @Test
    func `Empty logo lookups do not access the network`() async throws {
        let transport = StubTransport { try reply(to: $0, payload: #""result":[]"#) }
        #expect(try await HeliusRPC(apiKey: "fixture-key", network: .mainnet, transport: transport).logos(for: []).isEmpty)
        #expect(await transport.requests.isEmpty)
    }

    @Test
    func `Lookups split into batches of a thousand mints`() async throws {
        let transport = StubTransport { request in
            let unknown = Array(repeating: "null", count: try requestedIDs(request).count)
            return try reply(to: request, payload: #""result":[\#(unknown.joined(separator: ","))]"#)
        }
        let mints = (0..<1_001).map { "mint-\($0)" }

        #expect(try await HeliusRPC(apiKey: "fixture-key", network: .mainnet, transport: transport).logos(for: mints).isEmpty)

        let batches = try await transport.requests.map(requestedIDs)
        #expect(batches.map(\.count) == [1_000, 1])
        #expect(batches.flatMap(\.self) == mints)
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
}

private func requestedIDs(_ request: URLRequest) throws -> [String] {
    let parameters = try #require(try requestBody(request)["params"] as? [String: Any])
    return try #require(parameters["ids"] as? [String])
}
