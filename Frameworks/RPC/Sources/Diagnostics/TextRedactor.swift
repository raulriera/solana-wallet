import Foundation

/// A type that removes sensitive values from diagnostic text.
protocol TextRedactor: Sendable {
    /// Returns text with sensitive values replaced.
    ///
    /// - Parameter text: The diagnostic text to sanitize.
    /// - Returns: The input text with the implementation's redaction policy applied.
    func redact(_ text: String) -> String
}

/// A redactor that replaces configured secrets with a placeholder.
struct SecretRedactor: TextRedactor, CustomStringConvertible, CustomDebugStringConvertible {
    private let secrets: [String]

    /// Creates a redactor for a collection of sensitive values.
    ///
    /// Empty values are ignored. Longer values are replaced first so a key
    /// contained in an authenticated URL doesn't prevent that URL's replacement.
    ///
    /// - Parameter secrets: The exact strings to replace in diagnostic text.
    init(secrets: [String]) {
        self.secrets = secrets.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
    }

    /// Creates a redactor for endpoint URLs and each of their parts that can hold a key.
    ///
    /// Each URL is replaced whole, and so are its user, password, path components, and query values.
    ///
    /// - Parameter urls: The endpoints that diagnostic text must not reveal.
    init(urls: [URL]) {
        self.init(secrets: urls.flatMap { url in
            // A query item without a value, such as `?key`, holds the key in its name.
            let queries = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return [url.absoluteString, url.user(), url.password()].compactMap(\.self)
                + url.pathComponents.filter { $0 != "/" } + queries.map { $0.value ?? $0.name }
        })
    }

    /// A textual representation that omits the configured secrets.
    var description: String { "SecretRedactor" }

    /// A debugging representation that omits the configured secrets.
    var debugDescription: String { description }

    /// Replaces occurrences of the configured secrets with `[redacted]`.
    ///
    /// - Parameter text: The diagnostic text to sanitize.
    /// - Returns: The sanitized text, or the original text if no secret matches.
    func redact(_ text: String) -> String {
        secrets.reduce(text) { result, secret in
            result.replacingOccurrences(of: secret, with: "[redacted]", options: .literal)
        }
    }
}
