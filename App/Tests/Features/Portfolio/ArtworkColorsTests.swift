import Foundation
import Testing
@testable import widgets

struct ArtworkColorsTests {
    private let url = URL(string: "https://cdn.example.com/logo.png")!

    @Test
    func `A sampled logo color is reused without another load`() async throws {
        let png = try ArtworkFixture.png(center: (0.2, 0.5, 0.8))
        let log = RequestLog()
        let colors = ArtworkColors { request in
            await log.record()
            return (png, try success(for: request))
        }

        let first = await colors.color(for: url)
        let second = await colors.color(for: url)

        #expect(first != nil)
        #expect(second == first)
        #expect(await log.count == 1)
    }

    @Test
    func `A failed load is tried again`() async throws {
        let png = try ArtworkFixture.png(center: (0.2, 0.5, 0.8))
        let log = RequestLog()
        let colors = ArtworkColors { request in
            guard await log.record() > 1 else { throw URLError(.notConnectedToInternet) }
            return (png, try success(for: request))
        }

        #expect(await colors.color(for: url) == nil)
        #expect(await colors.color(for: url) != nil)
    }

    @Test
    func `A logo the provider can't serve has no color`() async {
        let colors = ArtworkColors { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil))
            return (try ArtworkFixture.png(center: (0.2, 0.5, 0.8)), response)
        }

        #expect(await colors.color(for: url) == nil)
    }

    @Test
    func `A logo over plain HTTP never loads`() async {
        let colors = ArtworkColors { _ in
            Issue.record("A plain HTTP logo was requested")
            throw URLError(.badURL)
        }

        #expect(await colors.color(for: URL(string: "http://cdn.example.com/logo.png")!) == nil)
    }

    @Test
    func `A bundled logo gives its own color`() async throws {
        let usdc = try #require(Bundle.main.url(forResource: "usdc", withExtension: "png"))
        let color = try #require(await ArtworkColors().color(for: usdc))
        #expect(color.blue > color.green && color.green > color.red)
    }
}

nonisolated private func success(for request: URLRequest) throws -> URLResponse {
    let url = try #require(request.url)
    return try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
}

private actor RequestLog {
    private(set) var count = 0

    @discardableResult
    func record() -> Int {
        count += 1
        return count
    }
}
