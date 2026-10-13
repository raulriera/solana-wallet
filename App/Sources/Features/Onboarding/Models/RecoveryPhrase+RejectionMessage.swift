import Foundation
import Wallet

extension RecoveryPhrase.ValidationError {
    /// Explains the rejection under the recovery words; the words must never be logged or used as identifiers.
    /// - Parameter phrase: The words as entered, read only to name an unknown word.
    /// - Returns: The explanation, or `nil` when an unknown word's position no longer exists in the phrase.
    func message(in phrase: String) -> LocalizedStringResource? {
        switch self {
        case .invalidWordCount:
            return "Check for missing or extra words."
        case .unknownWord(let position):
            let words = phrase.decomposedStringWithCompatibilityMapping.split(whereSeparator: \.isWhitespace)
            guard words.indices.contains(position) else { return nil }
            return "‘\(String(words[position]))’ isn't a valid recovery word."
        case .invalidChecksum, .invalidEntropy:
            return "These words don't form a valid recovery phrase. Check their spelling and order."
        }
    }
}
