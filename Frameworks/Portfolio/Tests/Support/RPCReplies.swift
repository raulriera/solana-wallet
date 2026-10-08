import Foundation
import Testing

/// Reads a JSON-RPC request's body.
/// - Parameter request: The HTTP request created by an RPC client.
/// - Returns: The request's JSON object.
/// - Throws: A JSON parsing error, or a test prerequisite error if the body is missing or isn't an object.
func rpcBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

/// Wraps a result in a successful JSON-RPC response to a request.
/// - Parameters:
///   - body: The request's JSON object, which supplies the response identifier.
///   - result: The method's result.
///   - request: The HTTP request, which supplies the response URL.
/// - Returns: The response data and HTTP metadata.
/// - Throws: A JSON encoding error, or a test prerequisite error if the request lacks an identifier or URL.
func rpcReply(to body: [String: Any], result: Any, request: URLRequest) throws -> (Data, URLResponse) {
    let envelope: [String: Any] = ["jsonrpc": "2.0", "id": try #require(body["id"]), "result": result]
    let url = try #require(request.url)
    return (try JSONSerialization.data(withJSONObject: envelope),
            try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
}

/// Encodes a DAS `getAssetBatch` result: a mint with a logo as an asset with its CDN copy, others as `null`.
/// - Parameters:
///   - mints: The mints the lookup asks for.
///   - logos: The CDN logo URL of each mint that has one.
/// - Returns: The result, in request order.
func assetBatch(for mints: [String], logos: [String: String]) -> [Any] {
    mints.map { mint -> Any in
        guard let logo = logos[mint] else { return NSNull() }
        return ["id": mint, "interface": "FungibleToken",
                "content": ["files": [["cdn_uri": logo, "mime": "image/png"]]]] as [String: Any]
    }
}
