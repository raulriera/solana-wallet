import Foundation
import Testing
@testable import RPC

/// Exercises DAS conversion through the real provider and its private HTTP boundary.
struct MetadataTests {
    /// Verifies all approved metadata groups retain their meaning and precision.
    @Test
    func `DAS metadata uses canonical fields and retains typed values`() async throws {
        let transport = StubTransport { try reply(to: $0, payload: #""result":\#(richAsset)"#) }
        let asset = try await HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport).send(GetAsset(id: "mint"))
        #expect(asset.name == "Example")
        #expect(asset.symbol == "EX")
        #expect(asset.imageURL?.absoluteString == "https://cdn.example.com/image")
        let metadata = try #require(asset.metadata)
        #expect(metadata.description == "Description")
        #expect(metadata.websiteURL?.absoluteString == "https://example.com")
        #expect(metadata.metadataURL?.absoluteString == "ar://metadata")
        #expect(metadata.kind == "FutureAssetKind")
        #expect(metadata.tokenStandard == "FutureStandard")
        #expect(metadata.isMutable == false)
        #expect(metadata.media == [.init(url: URL(string: "ipfs://image"), cdnURL: URL(string: "https://cdn.example.com/image"), mimeType: "image/png")])
        #expect(metadata.attributes == [
            .init(name: "amount", value: .number(Decimal(string: "9007199254740993.123456789")!), displayType: "number"),
            .init(name: "nested", value: .object(["enabled": .bool(true), "items": .array([.string("red"), .null])])),
            .init(name: "empty", value: .null),
        ])
        #expect(metadata.collections == [.init(id: "collection", name: "Collection", symbol: "COL",
            imageURL: URL(string: "https://example.com/collection.png"), description: "Collection description",
            websiteURL: URL(string: "https://example.com/collection"), isVerified: false)])
        #expect(metadata.creators == [.init(address: "creator", share: 100, isVerified: true)])
        let encoded = try JSONEncoder().encode(metadata)
        #expect(try JSONDecoder().decode(Metadata.self, from: encoded) == metadata)
        let json = String(decoding: encoded, as: UTF8.self)
        #expect(!json.contains("json_uri"))
        #expect(!json.contains("trait_type"))
        #expect(json.contains("metadataURL"))
        let request = try #require(await transport.requests.first)
        let body = try requestBody(request)
        #expect(body["method"] as? String == "getAsset")
        let params = try #require(body["params"] as? [String: Any])
        #expect(params["id"] as? String == "mint")
        #expect(params["options"] as? [String: Bool] == ["showCollectionMetadata": true, "showUnverifiedCollections": true])
    }

    /// Verifies bad optional values don't erase neighboring metadata.
    @Test
    func `Malformed optional metadata preserves valid fields and array entries`() throws {
        let asset = try JSONDecoder().decode(Asset.self, from: Data(#"""
        {"id":"mint","interface":"FungibleToken","mutable":false,
         "content":{"json_uri":"","metadata":{"name":"Wrapped SOL","description":false,
             "attributes":[false,{"trait_type":"valid","value":true}]},
             "links":{"image":"","external_url":false},
             "files":[false,{"cdn_uri":"https://example.com/sol.png","mime":"image/png"}]},
         "creators":[false,{"address":"creator","share":false,"verified":true}],
         "token_info":{"balance":18446744073709551615,"decimals":9}}
        """#.utf8))
        #expect(asset.name == "Wrapped SOL")
        #expect(asset.imageURL?.absoluteString == "https://example.com/sol.png")
        #expect(asset.metadata?.description == nil)
        #expect(asset.metadata?.metadataURL == nil)
        #expect(asset.metadata?.attributes == [.init(name: "valid", value: .bool(true))])
        #expect(asset.metadata?.creators == [.init(address: "creator", isVerified: true)])
        #expect(asset.metadata?.isMutable == false)
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

/// A provider-shaped fixture with descriptive metadata and extra fields the client ignores.
private let richAsset = #"""
{"id":"mint","interface":"FutureAssetKind","mutable":false,"burnt":false,
 "content":{"json_uri":"ar://metadata",
   "metadata":{"name":"Example","symbol":"EX","description":"Description","token_standard":"FutureStandard",
     "attributes":[{"trait_type":"amount","value":9007199254740993.123456789,"display_type":"number"},
       {"trait_type":"nested","value":{"enabled":true,"items":["red",null]}},{"trait_type":"empty","value":null}]},
   "links":{"image":"ipfs://image","external_url":"https://example.com"},
   "files":[{"uri":"ipfs://image","cdn_uri":"https://cdn.example.com/image","mime":"image/png"}]},
 "grouping":[{"group_key":"collection","group_value":"collection","verified":false,
   "collection_metadata":{"name":"Collection","symbol":"COL","image":"https://example.com/collection.png",
     "description":"Collection description","external_url":"https://example.com/collection"}}],
 "creators":[{"address":"creator","share":100,"verified":true}],
 "authorities":[{"address":"authority","scopes":["full"]}],
 "ownership":{"owner":"owner","ownership_model":"single","frozen":true,"delegated":true,"delegate":"delegate"},
 "royalty":{"royalty_model":"creators","target":"target","percent":0.042,"basis_points":420,"primary_sale_happened":true,"locked":false},
 "supply":{"print_max_supply":100,"print_current_supply":10,"edition_nonce":254},
 "compression":{"eligible":true,"compressed":true,"data_hash":"data","creator_hash":"creator","asset_hash":"asset",
   "tree":"tree","seq":9007199254740993,"leaf_id":3},
 "token_info":{"balance":9007199254740993,"decimals":9,"supply":18446744073709551615,
   "token_program":"program","mint_authority":"mint-authority","freeze_authority":"freeze-authority"}}
"""#
