import Foundation
import Testing
@testable import RPC

struct URLSessionTransportTests {
    private final class ServedBody: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url,
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                let length = query.first(where: { $0.name == "length" })?.value.flatMap(Int.init),
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: query.contains(URLQueryItem(name: "declared", value: "true"))
                        ? ["Content-Length": String(length)] : [:]
                )
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            let body = URLSessionTransportTests.body(count: length)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if query.contains(URLQueryItem(name: "stalled", value: "true")) {
                client?.urlProtocol(self, didLoad: body.prefix(16))
                return
            }
            for start in stride(from: 0, to: length, by: 16) {
                client?.urlProtocol(self, didLoad: body.subdata(in: start..<min(start + 16, length)))
            }
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    @Test(.timeLimit(.minutes(1)), arguments: [Int?.none, 64])
    func `A response that doesn't finish within the resource timeout fails`(maximumLength: Int?) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ServedBody.self]
        configuration.timeoutIntervalForRequest = 120
        let transport = URLSessionTransport(configuration: configuration, resourceTimeout: 0.5)
        var request = try Self.request(length: 64, declared: false, stalled: true)
        request.timeoutInterval = 120

        let error = await #expect(throws: URLError.self) {
            if let maximumLength {
                _ = try await transport.data(for: request, maximumLength: maximumLength)
            } else {
                _ = try await transport.data(for: request)
            }
        }

        #expect(error?.code == .timedOut)
    }

    @Test(arguments: [true, false])
    func `A bounded read returns a body as long as the limit`(declared: Bool) async throws {
        let (data, _) = try await Self.transport().data(
            for: Self.request(length: 64, declared: declared),
            maximumLength: 64
        )

        #expect(data == Self.body(count: 64))
    }

    @Test(arguments: [true, false])
    func `A bounded read refuses a longer body whether or not its length is declared`(declared: Bool) async {
        await #expect(throws: RPCError.invalidResponse(.oversized)) {
            try await Self.transport().data(for: Self.request(length: 65, declared: declared), maximumLength: 64)
        }
    }

    private static func transport() -> URLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ServedBody.self]
        return URLSessionTransport(configuration: configuration)
    }

    private static func request(length: Int, declared: Bool, stalled: Bool = false) throws -> URLRequest {
        URLRequest(url: try #require(URL(
            string: "https://transport.test/body?length=\(length)&declared=\(declared)&stalled=\(stalled)"
        )))
    }

    private static func body(count: Int) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0) })
    }
}
