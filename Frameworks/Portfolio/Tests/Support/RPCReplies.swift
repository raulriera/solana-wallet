import Foundation
import Testing

func rpcReply(to body: [String: Any], result: Any, request: URLRequest) throws -> (Data, URLResponse) {
    let envelope: [String: Any] = ["jsonrpc": "2.0", "id": try #require(body["id"]), "result": result]
    let url = try #require(request.url)
    return (try JSONSerialization.data(withJSONObject: envelope),
            try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
}

func assetBatch(for mints: [String], logos: [String: String]) -> [Any] {
    mints.map { mint -> Any in
        guard let logo = logos[mint] else { return NSNull() }
        return ["id": mint, "interface": "FungibleToken",
                "content": ["files": [["cdn_uri": logo, "mime": "image/png"]]]] as [String: Any]
    }
}
