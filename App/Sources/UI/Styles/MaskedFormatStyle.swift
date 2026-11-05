import Foundation

/// Formats text that can hold a key, showing its first four characters and a dot for each other character.
nonisolated struct MaskedFormatStyle: FormatStyle {
    /// Whether the output says the rest is hidden instead of showing dots.
    var isSpoken = false

    func format(_ text: String) -> String {
        let shown = String(text.prefix(4))
        let hidden = text.count - shown.count
        guard hidden > 0 else { return shown }
        return isSpoken
            ? String(localized: "\(shown), rest hidden", comment: "VoiceOver text for a key, or part of a URL, that shows only its first characters. The variable is those characters.")
            : shown + String(repeating: "•", count: hidden)
    }
}

nonisolated extension FormatStyle where Self == MaskedFormatStyle {
    static var masked: Self { Self() }

    static var spokenMasked: Self { Self(isSpoken: true) }
}
