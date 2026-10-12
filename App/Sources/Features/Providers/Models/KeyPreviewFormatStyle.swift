import Foundation

/// Formats a saved key, such as an API key, with only its first four characters shown, so most of it stays hidden.
///
/// The output depends only on those characters and the key's length, so a preview formats the same as its key.
nonisolated struct KeyPreviewFormatStyle: FormatStyle {
    /// Whether the output keeps a dot for each hidden character, rather than only the shown characters.
    var includesHidden = true

    /// Formats the key with its hidden characters masked or left out.
    /// - Parameter key: The key, or a preview of it.
    /// - Returns: The first four characters, followed by a dot for each other character when hidden ones are included.
    func format(_ key: String) -> String {
        let start = String(key.prefix(4))
        return includesHidden ? start + String(repeating: "•", count: key.count - start.count) : start
    }
}

nonisolated extension FormatStyle where Self == KeyPreviewFormatStyle {
    /// A key with every character after its first four shown as a dot.
    static var keyPreview: Self { Self() }

    /// Only a key's first four characters, which VoiceOver reads in place of the dots.
    static var keyStart: Self { Self(includesHidden: false) }
}
