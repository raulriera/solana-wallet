import Foundation
import Testing
@testable import RPC

actor StubTransport: HTTPTransport {
    typealias Responder = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private(set) var requests: [URLRequest] = []
    private(set) var observedCancellation = false
    private let respond: Responder

    init(respond: @escaping Responder) {
        self.respond = respond
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        do {
            return try await respond(request)
        } catch {
            observedCancellation = Task.isCancelled
            throw error
        }
    }
}

extension Solana {
    static func devnet(transport: StubTransport) -> Solana {
        Solana(network: .devnet, transport: transport)
    }
}

func requestBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

func reply(
    to request: URLRequest,
    payload: String,
    status: Int = 200,
    headers: [String: String] = [:],
    id: String? = nil
) throws -> (Data, URLResponse) {
    let requestID = try #require(requestBody(request)["id"] as? String)
    let url = try #require(request.url)
    let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers))
    let data = Data(#"{"jsonrpc":"2.0","id":"\#(id ?? requestID)",\#(payload)}"#.utf8)
    return (data, response)
}

func httpReply(to request: URLRequest, body: String, status: Int = 200,
               headers: [String: String] = [:]) throws -> (Data, URLResponse) {
    let url = try #require(request.url)
    let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers))
    return (Data(body.utf8), response)
}

func requestedMints(_ request: URLRequest, query name: String) throws -> [String] {
    let url = try #require(request.url)
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    let mints = try #require(query?.first { $0.name == name }?.value)
    return mints.split(separator: ",").map(String.init)
}
