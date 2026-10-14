import Foundation
import Testing
@testable import RPC

/// Exercises DAS asset decoding through the real provider and its private HTTP boundary.
struct AssetTests {
    /// Verifies a lookup sends only the identifier and keeps the asset's identity and CDN image from a full response.
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

    /// Verifies malformed file entries are skipped without losing a valid image beside them.
    @Test
    func `Malformed files keep the valid image`() throws {
        let asset = try JSONDecoder().decode(Asset.self, from: Data(#"""
        {"id":"mint","interface":"FungibleToken",
         "content":{"files":[false,{"cdn_uri":false},{"cdn_uri":"https://example.com/sol.png","mime":"image/png"}]}}
        """#.utf8))

        #expect(asset.imageURL?.absoluteString == "https://example.com/sol.png")
    }

    /// Verifies the image comes from the provider's HTTPS copy instead of the creator's own link.
    @Test
    func `The image is the provider's HTTPS CDN copy`() throws {
        let asset = try JSONDecoder().decode(Asset.self, from: Data(#"""
        {"id":"mint","interface":"FungibleToken",
         "content":{"links":{"image":"https://creator.example/logo.png"},
             "files":[{"uri":"https://creator.example/logo.png","cdn_uri":"https://cdn.example.com/logo.png","mime":"image/png"}]}}
        """#.utf8))
        #expect(asset.imageURL?.absoluteString == "https://cdn.example.com/logo.png")
    }

    /// Verifies an image never reveals the viewer to the creator's host or over plain HTTP.
    /// - Parameter files: Image files without an HTTPS copy from the provider.
    @Test(arguments: [
        #"[{"uri":"https://creator.example/logo.png","mime":"image/png"}]"#,
        #"[{"uri":"https://creator.example/logo.png","cdn_uri":"http://cdn.example.com/logo.png","mime":"image/png"}]"#,
    ])
    func `Creator links and plain HTTP copies are never the image`(files: String) throws {
        let asset = try JSONDecoder().decode(Asset.self, from: Data(#"""
        {"id":"mint","interface":"FungibleToken",
         "content":{"links":{"image":"https://creator.example/logo.png"},"files":\#(files)}}
        """#.utf8))
        #expect(asset.imageURL == nil)
    }
}

/// A provider-shaped fixture with descriptive fields the client ignores.
private let providerAsset = #"""
{"id":"mint","interface":"FutureAssetKind","mutable":false,"burnt":false,
 "content":{"json_uri":"ar://metadata",
   "metadata":{"name":"Example","symbol":"EX","description":"Description","token_standard":"FutureStandard"},
   "links":{"image":"ipfs://image","external_url":"https://example.com"},
   "files":[{"uri":"ipfs://image","cdn_uri":"https://cdn.example.com/image","mime":"image/png"}]},
 "creators":[{"address":"creator","share":100,"verified":true}],
 "token_info":{"balance":9007199254740993,"decimals":9,"supply":18446744073709551615}}
"""#
