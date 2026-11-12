import Algorithms
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
                        ? ["Content-Type": "application/octet-stream", "Content-Length": String(length)]
                        : ["Content-Type": "application/octet-stream"]
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
            for chunk in body.chunks(ofCount: 16) {
                client?.urlProtocol(self, didLoad: chunk)
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

    @Test(.timeLimit(.minutes(1)))
    func `A bounded read stops a body as soon as it grows longer than the limit`() async {
        await #expect(throws: RPCError.invalidResponse(.oversized)) {
            try await Self.transport().data(
                for: Self.request(length: 64, declared: false, stalled: true),
                maximumLength: 8
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `A cancelled bounded read stops waiting for the body`() async throws {
        let request = try Self.request(length: 64, declared: false, stalled: true)
        let read = Task { try await Self.transport().data(for: request, maximumLength: 64) }

        read.cancel()

        let error = await #expect(throws: URLError.self) { try await read.value }
        #expect(error?.code == .cancelled)
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
