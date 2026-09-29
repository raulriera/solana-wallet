import Foundation
import Testing
@testable import RPC

/// DAS HTTP fixtures decoded by the real RPC client during portfolio refreshes.
actor AssetResponses: HTTPTransport {
    private nonisolated let network: Network
    private(set) var requests: [GetAssetsByOwner] = []
    private let respond: @Sendable (GetAssetsByOwner) async throws -> Data

    /// The real provider client receiving the fixture's HTTP responses.
    nonisolated var client: HeliusRPC {
        HeliusRPC(apiKey: "fixture-key", network: network, transport: self)
    }

    /// Creates isolated responses for pagination, cache, and cancellation checks.
    /// - Parameters:
    ///   - network: The network associated with cached snapshots.
    ///   - respond: The JSON page supplier, optionally suspending or failing a request.
    init(network: Network = .mainnet, respond: @escaping @Sendable (GetAssetsByOwner) async throws -> Data) {
        self.network = network
        self.respond = respond
    }

    /// Records encoded DAS parameters and returns a matching JSON-RPC envelope.
    /// - Parameter request: The HTTP request created by HeliusRPC.
    /// - Returns: The fixture's response data and HTTP metadata.
    /// - Throws: A fixture, transport, or cancellation error.
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try #require(body["method"] as? String == "getAssetsByOwner")
        let params = try #require(body["params"] as? [String: Any])
        let query = try GetAssetsByOwner(owner: #require(params["ownerAddress"] as? String),
            page: #require(params["page"] as? Int), limit: #require(params["limit"] as? Int),
            includesNativeBalance: #require((params["options"] as? [String: Bool])?["showNativeBalance"]))
        requests.append(query)
        let result = try await respond(query)
        let id = try #require(body["id"] as? String)
        let envelope = Data(#"{"jsonrpc":"2.0","id":"\#(id)","result":\#(String(decoding: result, as: UTF8.self))}"#.utf8)
        let url = try #require(request.url)
        return (envelope, try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
    }
}
