import Foundation

/// Formats a BIP-39 passphrase with each space at its start and end marked.
nonisolated struct PassphraseFormatStyle: FormatStyle {
    var isSpoken = false

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
    /// A style that shows each space at a passphrase's start and end as `␣`.
    static var passphrase: Self { Self() }

    /// A style that names each space at a passphrase's start and end.
    static var spokenPassphrase: Self { Self(isSpoken: true) }
}
