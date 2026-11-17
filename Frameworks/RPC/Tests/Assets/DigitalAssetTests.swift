import Foundation
import Testing
@testable import RPC

struct DigitalAssetTests {
    @Test
    func `An asset lookup keeps its identity and CDN image`() async throws {
        let transport = StubTransport { try reply(to: $0, payload: #""result":\#(providerAsset)"#) }
        let asset = try await HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport).send(GetAsset(id: "mint"))

        #expect(asset.id == "mint")
        #expect(asset.imageURL?.absoluteString == "https://cdn.example.com/image")
        let request = try #require(await transport.requests.first)
        let body = try requestBody(request)
        #expect(body["method"] as? String == "getAsset")
        #expect(body["params"] as? [String: String] == ["id": "mint"])
    }

    @Test
    func `Malformed files keep the valid image`() throws {
        let asset = try JSONDecoder().decode(DigitalAsset.self, from: Data(#"""
        {"id":"mint","interface":"FungibleToken",
         "content":{"files":[false,{"cdn_uri":false},{"cdn_uri":"https://example.com/sol.png","mime":"image/png"}]}}
        """#.utf8))

        #expect(asset.imageURL?.absoluteString == "https://example.com/sol.png")
    }

    @Test(arguments: [
        #"[{"uri":"https://creator.example/logo.png","mime":"image/png"}]"#,
        #"[{"uri":"https://creator.example/logo.png","cdn_uri":"http://cdn.example.com/logo.png","mime":"image/png"}]"#,
    ])
    func `Creator links and plain HTTP copies are never the image`(files: String) throws {
        let asset = try JSONDecoder().decode(DigitalAsset.self, from: Data(#"""
        {"id":"mint","interface":"FungibleToken",
         "content":{"links":{"image":"https://creator.example/logo.png"},"files":\#(files)}}
        """#.utf8))
        #expect(asset.imageURL == nil)
    }
}

private let providerAsset = #"""
{"id":"mint","interface":"FutureAssetKind","mutable":false,"burnt":false,
 "content":{"json_uri":"ar://metadata",
   "metadata":{"name":"Example","symbol":"EX","description":"Description","token_standard":"FutureStandard"},
   "links":{"image":"ipfs://image","external_url":"https://example.com"},
   "files":[{"uri":"ipfs://image","cdn_uri":"https://cdn.example.com/image","mime":"image/png"}]},
 "creators":[{"address":"creator","share":100,"verified":true}],
 "token_info":{"balance":9007199254740993,"decimals":9,"supply":18446744073709551615}}
"""#
