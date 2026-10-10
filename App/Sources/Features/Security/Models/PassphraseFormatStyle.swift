import Foundation

/// Formats a BIP-39 passphrase for the recovery backup so that spaces at its start and end, which change the
/// wallet but don't show in text, stay noticeable.
///
/// Each such space appears as `␣`, and VoiceOver hears it as "space". Spaces inside the passphrase stay as typed.
nonisolated struct PassphraseFormatStyle: FormatStyle {
    /// Whether the output is for VoiceOver rather than for display.
    var isSpoken = false

    /// Formats the passphrase with each space at its start and end marked.
    /// - Parameter passphrase: The original passphrase.
    /// - Returns: The passphrase as the backup shows or speaks it.
    func format(_ passphrase: String) -> String {
        let start = passphrase.firstIndex { !$0.isWhitespace } ?? passphrase.endIndex
        let end = passphrase.lastIndex { !$0.isWhitespace }.map(passphrase.index(after:)) ?? start
        let mark = isSpoken ? String(localized: "space", comment: "VoiceOver name for a space at the start or end of a passphrase.") : "␣"
        let leading = Array(repeating: mark, count: passphrase.distance(from: passphrase.startIndex, to: start))
        let trailing = Array(repeating: mark, count: passphrase.distance(from: end, to: passphrase.endIndex))
        let middle = start < end ? [String(passphrase[start..<end])] : []
        return (leading + middle + trailing).joined(separator: isSpoken ? ", " : "")
    }
}

nonisolated extension FormatStyle where Self == PassphraseFormatStyle {
    /// A passphrase for display, with `␣` for each space at its start and end.
    static var passphrase: Self { Self() }

    /// A passphrase for VoiceOver, which names each space at its start and end.
    static var spokenPassphrase: Self { Self(isSpoken: true) }
}
