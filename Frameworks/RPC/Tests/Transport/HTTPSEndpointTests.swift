import Foundation
import Testing
@testable import RPC

struct HTTPSEndpointTests {
    @Test(arguments: [
        ("https://rpc.example.com/v1?key=fixture-key", "https://rpc.example.com/v1?key=fixture-key"),
        ("HTTPS://rpc.example.com", "HTTPS://rpc.example.com"),
    ])
    func `HTTPS URLs with a host are endpoints`(text: String, expected: String) throws {
        #expect(try #require(URL(string: text)).httpsEndpoint?.absoluteString == expected)
    }

    @Test
    func `A relative URL resolves against its HTTPS base`() throws {
        let url = try #require(URL(string: "v1", relativeTo: URL(string: "https://rpc.example.com/")))
        #expect(url.httpsEndpoint?.absoluteString == "https://rpc.example.com/v1")
    }

    @Test(arguments: ["http://rpc.example.com", "wss://rpc.example.com", "https://", "rpc.example.com", "file:///tmp"])
    func `Other URLs are not endpoints`(_ text: String) throws {
        #expect(try #require(URL(string: text)).httpsEndpoint == nil)
    }
}
