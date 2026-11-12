import Foundation
import Redaction

/// A type that removes sensitive values from diagnostic text.
protocol TextRedactor: Sendable {
    /// Returns text with sensitive values replaced.
    ///
    /// - Parameter text: The diagnostic text.
    /// - Returns: The redacted text.
    func redact(_ text: String) -> String
}

/// A redactor that replaces configured secrets with a placeholder.
struct SecretRedactor: TextRedactor, Redacted {
    private let secrets: [String]

    /// Creates a redactor for sensitive values.
    ///
    /// - Parameter secrets: The exact strings to replace.
    init(secrets: [String]) {
        self.secrets = secrets.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
    }

    /// Creates a redactor for endpoint URLs and each of their parts that can hold a key.
    ///
    /// - Parameter urls: The endpoints to redact.
    init(urls: [URL]) {
        self.init(secrets: urls.flatMap { url in
            let queries = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return [url.absoluteString, url.user(), url.password()].compactMap(\.self)
                + url.pathComponents.filter { $0 != "/" } + queries.map { $0.value ?? $0.name }
        })
    }

    func redact(_ text: String) -> String {
        secrets.reduce(text) { result, secret in
            result.replacingOccurrences(of: secret, with: "[redacted]", options: .literal)
        }
    }
}
