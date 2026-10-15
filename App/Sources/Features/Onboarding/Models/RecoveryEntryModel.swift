import Observation
import Wallet

/// Keeps recovery entry transient and updates validation at the input's mutation boundary.
@MainActor
@Observable
final class RecoveryEntryModel {
    var phrase = "" {
        didSet {
            // Switching between the hidden and shown fields writes the same words back; only an edit clears the check.
            guard phrase != oldValue else { return }
            hasPhrase = phrase.contains { !$0.isWhitespace }
            rejection = nil
        }
    }
    var passphrase = ""
    var showsWords = false
    var showsPassphrase = false
    private(set) var hasPhrase = false
    /// Why the words can't be used, or `nil` while they haven't been checked or are valid.
    private(set) var rejection: RecoveryPhrase.ValidationError?
    /// Counts rejected checks, so each rejection signals again while the same rejection stays on screen.
    private(set) var rejectionCount = 0

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

    /// Checks local BIP-39 validity, including when editing ends without submitting, and counts each rejection.
    /// - Returns: Whether word count, English words, and checksum are valid.
    @discardableResult
    func validate() -> Bool {
        do {
            _ = try RecoveryPhrase(phrase)
            rejection = nil
            return true
        } catch let error as RecoveryPhrase.ValidationError {
            rejection = error
        } catch {
            // Unknown failures cross the recovery boundary without retaining their contents.
            rejection = .invalidEntropy
        }
        rejectionCount += 1
        return false
    }

    /// Releases input references when phrase entry ends; Swift does not guarantee memory erasure.
    func clear() {
        phrase = ""
        passphrase = ""
        rejection = nil
        showsWords = false
        showsPassphrase = false
    }
}
