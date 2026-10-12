import Foundation

/// Formats part of an RPC URL that can be a key with only its first four characters shown, so most of it stays
/// hidden.
nonisolated struct ShortenedFormatStyle: FormatStyle {
    /// Formats the text with everything after its first four characters replaced by "…".
    /// - Parameter text: The text to shorten.
    /// - Returns: The text as people see it; text of four characters or fewer stays as it is.
    func format(_ text: String) -> String {
        text.count > 4 ? "\(text.prefix(4))…" : text
    }
}

nonisolated extension FormatStyle where Self == ShortenedFormatStyle {
    /// Text with only its first four characters shown.
    static var shortened: Self { Self() }
}
