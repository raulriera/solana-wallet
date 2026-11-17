import Foundation
import Testing
@testable import RPC

private let customEndpoint = "https://fixture-user:fixture-pass@rpc.example.com/path-token?api-key=query-key&bare-key"

struct SecretRedactorTests {
    @Test
    func `Redaction replaces API keys and authenticated URLs and keeps other text`() {
        let key = "test-key"
        let endpoint = "https://devnet.helius-rpc.com/?api-key=\(key)"
        let redactor: any TextRedactor = SecretRedactor(secrets: [key, endpoint])

        #expect(redactor.redact("Request \(endpoint) failed for \(key); retry with \(key).")
            == "Request [redacted] failed for [redacted]; retry with [redacted].")
        #expect(redactor.redact("Retry after five seconds.") == "Retry after five seconds.")
    }

    @Test(arguments: [customEndpoint, "fixture-user", "fixture-pass", "path-token", "query-key", "bare-key"])
    func `Endpoint redaction replaces the URL and each part that can hold a key`(part: String) throws {
        let redactor = SecretRedactor(urls: [try #require(URL(string: customEndpoint))])

        let message = redactor.redact("Request failed for \(part).")

        #expect(message == "Request failed for [redacted].")
    }

    @Test
    func `Dumps of clients reveal no key`() throws {
        let endpoint = try #require(URL(string: "https://rpc.example.com/fixture-key"))
        let custom = try #require(SolanaRPC(endpoint: endpoint, network: .mainnet))
        var text = ""
        dump(HeliusRPC(apiKey: "fixture-key", network: .devnet), to: &text)
        dump(custom, to: &text)

        #expect(!text.contains("fixture-key"))
        #expect(!text.contains("example.com") && !text.contains("helius-rpc.com"))
    }
}
