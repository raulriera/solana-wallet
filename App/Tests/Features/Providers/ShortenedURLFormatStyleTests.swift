import Foundation
import Testing
@testable import widgets

/// Verifies that a custom RPC's URL shows enough to recognize it while most of a key in it stays hidden.
struct ShortenedURLFormatStyleTests {
    /// The host shows in full, and only the start of each path part and query value.
    /// - Parameters:
    ///   - entry: The saved URL.
    ///   - shown: The URL as people see it.
    /// - Throws: A test prerequisite error.
    @Test(arguments: [
        ("https://my-node.ngrok.app", "https://my-node.ngrok.app"),
        ("https://mainnet.example.com/?api-key=a1b2c3d4", "https://mainnet.example.com?api-key=a1b2…"),
        ("https://rpc.example.com:8443/v2/abcdefgh?token", "https://rpc.example.com:8443/v2/abcd…?toke…"),
    ])
    func `A custom RPC's URL is shortened for display`(entry: String, shown: String) throws {
        let url = try #require(URL(string: entry))

        #expect(ShortenedURLFormatStyle.shortenedURL.format(url) == shown)
    }
}
