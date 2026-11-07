import Foundation
import Testing
@testable import widgets

struct MaskedURLFormatStyleTests {
    @Test(arguments: [
        ("https://my-node.ngrok.app", "https://my-node.ngrok.app"),
        ("https://mainnet.example.com/?api-key=a1b2c3d4", "https://mainnet.example.com?api-key=a1b2••••"),
        ("https://rpc.example.com:8443/v2/abcdefgh?token", "https://rpc.example.com:8443/v2/abcd••••?toke•"),
    ])
    func `A custom RPC's URL is masked for display`(entry: String, shown: String) throws {
        let url = try #require(URL(string: entry))

        #expect(MaskedURLFormatStyle.maskedURL.format(url) == shown)
    }
}
