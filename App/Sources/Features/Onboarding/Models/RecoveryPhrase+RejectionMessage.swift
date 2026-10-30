import Foundation
import Wallet

extension RecoveryPhrase.ValidationError {
    /// Returns the explanation of the rejection.
    ///
    /// - Parameter phrase: The words as entered.
    /// - Returns: The explanation, or `nil` when the unknown word's position is outside the phrase.
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
