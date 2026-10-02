import Testing
@testable import RPC

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
}
