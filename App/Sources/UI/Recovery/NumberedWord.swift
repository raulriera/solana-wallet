import Redaction

/// A recovery word and its one-based position in the phrase.
nonisolated struct NumberedWord: Identifiable, Redacted {
    let position: Int
    let text: String

    var id: Int { position }
}
