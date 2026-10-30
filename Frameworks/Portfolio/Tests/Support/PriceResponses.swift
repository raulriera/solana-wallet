import Foundation
import Testing
@testable import RPC

actor PriceResponses: HTTPTransport {
    private(set) var requests: [[String]] = []
    private let status: Int
    private let respond: @Sendable ([String]) async throws -> Data

    nonisolated var client: Jupiter { Jupiter(transport: self) }

    init(status: Int = 200, respond: @escaping @Sendable ([String]) async throws -> Data) {
        self.status = status
        self.respond = respond
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let ids = try #require(components.queryItems?.first { $0.name == "ids" }?.value)
        let mints = ids.split(separator: ",").map(String.init)
        requests.append(mints)
        let body = try await respond(mints)
        return (body, try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                                 headerFields: ["Retry-After": "2"])))
    }
}
