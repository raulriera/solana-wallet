import Foundation
import Testing
@testable import RPC

/// A custom endpoint whose credentials, path, and query can each hold a key.
private let customEndpoint = "https://fixture-user:fixture-pass@rpc.example.com/path-token?api-key=query-key&bare-key"

/// Tests diagnostic text redaction independently of RPC requests.
struct SecretRedactorTests {
    /// Verifies replacement of complete authenticated URLs and repeated API keys.
    @Test
    func `Redaction replaces API keys and authenticated URLs`() {
        let key = "test-key"
        let endpoint = "https://devnet.helius-rpc.com/?api-key=\(key)"
        let redactor: any TextRedactor = SecretRedactor(secrets: [key, endpoint])

        let message = redactor.redact("Request \(endpoint) failed for \(key); retry with \(key).")

        #expect(message == "Request [redacted] failed for [redacted]; retry with [redacted].")
    }

    /// Verifies that messages without configured secrets retain their original text.
    @Test
    func `Redaction preserves messages without credentials`() {
        let redactor = SecretRedactor(secrets: ["test-key"])

        let message = redactor.redact("Retry after five seconds.")

        #expect(message == "Retry after five seconds.")
    }

    /// Verifies that endpoint redaction replaces the URL and each part of it that can hold a key.
    /// - Parameter part: The whole URL, or its user, password, path component, query value, or bare query name.
    @Test(arguments: [customEndpoint, "fixture-user", "fixture-pass", "path-token", "query-key", "bare-key"])
    func `Endpoint redaction replaces the URL and each part that can hold a key`(part: String) throws {
        let redactor = SecretRedactor(urls: [try #require(URL(string: customEndpoint))])

        let message = redactor.redact("Request failed for \(part).")

        #expect(message == "Request failed for [redacted].")
    }
}
