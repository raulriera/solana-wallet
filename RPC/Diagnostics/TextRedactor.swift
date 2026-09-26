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
