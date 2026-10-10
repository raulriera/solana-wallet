import Observation
import SwiftUI
import Wallet

/// Keeps recovery entry transient and updates validation at the input's mutation boundary.
@MainActor
@Observable
final class RecoveryInput {
    var phrase: String {
        didSet {
            // Switching between the hidden and shown fields writes the same words back; only an edit clears the check.
            guard phrase != oldValue else { return }
            hasPhrase = phrase.contains { !$0.isWhitespace }
            withAnimation { validationError = nil }
        }
    }
    var passphrase = ""
    var showsWords = false
    var showsPassphrase = false
    private(set) var hasPhrase: Bool
    private(set) var validationError: RecoveryPhrase.ValidationError?

    /// Native focus identity contains no recovery material and has constant-time equality.
    enum Field: UInt8, Hashable {
        case hiddenPhrase = 1, revealedPhrase, passphrase, revealedPassphrase

        var isPhrase: Bool {
            switch self {
            case .hiddenPhrase, .revealedPhrase: true
            case .passphrase, .revealedPassphrase: false
            }
        }
    }

    /// The focus identity of the recovery words control currently shown.
    var phraseField: Field { showsWords ? .revealedPhrase : .hiddenPhrase }

    /// The focus identity of the passphrase control currently shown.
    var passphraseField: Field { showsPassphrase ? .revealedPassphrase : .passphrase }

    /// Seeds optional public-fixture preview input once without replacing subsequent edits.
    /// - Parameter phrase: Empty for normal imports; public fixture words in previews.
    init(phrase: String = "") {
        self.phrase = phrase
        // Initialize derived state directly; editing animations must not run during construction.
        hasPhrase = phrase.contains { !$0.isWhitespace }
    }

    /// A local-only explanation; supplied words must never be logged or used as identifiers.
    var validationMessage: String? {
        switch validationError {
        case .invalidWordCount:
            return String(localized: "Check for missing or extra words.")
        case .unknownWord(let position):
            let words = phrase.decomposedStringWithCompatibilityMapping.split(whereSeparator: \.isWhitespace)
            guard words.indices.contains(position) else { return nil }
            return String(localized: "‘\(words[position])’ isn't a valid recovery word.")
        case .invalidChecksum, .invalidEntropy:
            return String(localized: "These words don't form a valid recovery phrase. Check their spelling and order.")
        case nil:
            return nil
        }
    }

    /// Checks local BIP-39 validity, including when editing ends without submitting.
    /// - Returns: Whether word count, English words, and checksum are valid.
    @discardableResult
    func validate() -> Bool {
        withAnimation {
            do {
                _ = try RecoveryPhrase(phrase)
                validationError = nil
                return true
            } catch let error as RecoveryPhrase.ValidationError {
                validationError = error
            } catch {
                // Unknown failures cross the recovery boundary without retaining their contents.
                validationError = .invalidEntropy
            }
            return false
        }
    }

    /// Releases input references when phrase entry ends; Swift does not guarantee memory erasure.
    func clear() {
        phrase = ""
        passphrase = ""
        validationError = nil
        showsWords = false
        showsPassphrase = false
    }
}
