import Foundation
import Testing
@testable import RPC

/// DAS HTTP fixtures decoded by the real RPC client during portfolio refreshes.
actor AssetResponses: HTTPTransport {
    /// Supplies a JSON result for a fungible-asset page query.
    typealias PageResponder = @Sendable (GetFungibleAssetsByOwner) async throws -> Data

    /// Supplies a JSON result for an individual asset identifier.
    typealias AssetResponder = @Sendable (String) async throws -> Data

    private nonisolated let network: Network
    private(set) var requests: [GetFungibleAssetsByOwner] = []
    private(set) var assetRequests: [String] = []
    private let respond: PageResponder
    private let assetResponse: AssetResponder

    /// The real provider client receiving the fixture's HTTP responses.
    nonisolated var client: HeliusRPC {
        HeliusRPC(apiKey: "fixture-key", network: network, transport: self)
    }

    /// Creates isolated responses for pagination, cache, and cancellation checks.
    /// - Parameters:
    ///   - network: The network associated with cached snapshots.
    ///   - assetResponse: The single-asset response supplier for the native mint image.
    ///   - respond: The JSON page supplier, optionally suspending or failing a request.
    init(network: Network = .mainnet,
         assetResponse: @escaping AssetResponder = { id in
             Data(#"{"id":"\#(id)","interface":"FungibleToken","content":{"metadata":{"name":"Wrapped SOL","symbol":"SOL"},"links":{"image":"https://example.com/sol.png"}}}"#.utf8)
         }, respond: @escaping PageResponder) {
        self.network = network
        self.respond = respond
        self.assetResponse = assetResponse
    }

    /// Records encoded DAS parameters and returns a matching JSON-RPC envelope.
    /// - Parameter request: The HTTP request created by HeliusRPC.
    /// - Returns: The fixture's response data and HTTP metadata.
    /// - Throws: A fixture, transport, or cancellation error.
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let params = try #require(body["params"] as? [String: Any])
        let result: Data
        if body["method"] as? String == "getAsset" {
            let id = try #require(params["id"] as? String)
            assetRequests.append(id)
            result = try await assetResponse(id)
        } else {
            try #require(body["method"] as? String == "searchAssets")
            #expect(params["tokenType"] as? String == "fungible")
            let options = try #require(params["options"] as? [String: Bool])
            #expect(options["showCollectionMetadata"] == true)
            #expect(options["showUnverifiedCollections"] == true)
            try #require(options["showNativeBalance"] != nil)
            let query = try GetFungibleAssetsByOwner(owner: #require(params["ownerAddress"] as? String),
                page: #require(params["page"] as? Int), limit: #require(params["limit"] as? Int),
                includesNativeBalance: options["showNativeBalance"] == true)
            requests.append(query)
            result = try await respond(query)
        }
        let id = try #require(body["id"] as? String)
        let envelope = Data(#"{"jsonrpc":"2.0","id":"\#(id)","result":\#(String(decoding: result, as: UTF8.self))}"#.utf8)
        let url = try #require(request.url)
        return (envelope, try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
    }
}
