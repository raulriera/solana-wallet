import Foundation

/// Formats text that can hold a key, such as an API key or part of an RPC URL, with only its first four characters
/// shown and a dot for each other character, so most of it stays hidden.
///
/// The output depends only on those characters and the text's length, so masked text formats the same again.
nonisolated struct MaskedFormatStyle: FormatStyle {
    /// Whether the output is for VoiceOver, which hears that the rest is hidden instead of each dot.
    var isSpoken = false

    /// Formats the text with everything after its first four characters masked.
    /// - Parameter text: The text, or masked text.
    /// - Returns: The text as people see or hear it; text of four characters or fewer stays as it is.
    func format(_ text: String) -> String {
        let shown = String(text.prefix(4))
        let hidden = text.count - shown.count
        guard hidden > 0 else { return shown }
        return isSpoken
            ? String(localized: "\(shown), rest hidden", comment: "VoiceOver text for a key, or part of an RPC URL, that shows only its first characters. The variable is those characters.")
            : shown + String(repeating: "•", count: hidden)
    }
}

nonisolated extension FormatStyle where Self == MaskedFormatStyle {
    /// Text with every character after its first four shown as a dot.
    static var masked: Self { Self() }

    /// Masked text for VoiceOver, which hears its first four characters and that the rest is hidden.
    static var spokenMasked: Self { Self(isSpoken: true) }
}
