import Observation
import Wallet

/// The recovery words and passphrase that phrase entry edits, with their validation.
@MainActor
@Observable
final class RecoveryEntryModel {
    var phrase = "" {
        didSet {
            guard phrase != oldValue else { return }
            hasPhrase = phrase.contains { !$0.isWhitespace }
            rejection = nil
        }
    }
    var passphrase = ""
    var showsWords = false
    var showsPassphrase = false
    private(set) var hasPhrase = false
    /// The reason the words were rejected, or `nil` when they weren't.
    private(set) var rejection: RecoveryPhrase.ValidationError?
    private(set) var rejectionCount = 0

    /// A focusable field of recovery entry.
    enum Field: UInt8, Hashable {
        case hiddenPhrase = 1, revealedPhrase, passphrase, revealedPassphrase

        var isPhrase: Bool {
            switch self {
            case .hiddenPhrase, .revealedPhrase: true
            case .passphrase, .revealedPassphrase: false
            }
        }
    }

    /// The focus identity of the visible recovery words field.
    var phraseField: Field { showsWords ? .revealedPhrase : .hiddenPhrase }

    /// The focus identity of the visible passphrase field.
    var passphraseField: Field { showsPassphrase ? .revealedPassphrase : .passphrase }

    /// Checks the recovery words and records any rejection.
    ///
    /// - Returns: Whether the words form a valid recovery phrase.
    @discardableResult
    func validate() -> Bool {
        do {
            _ = try RecoveryPhrase(phrase)
            rejection = nil
            return true
        } catch let error as RecoveryPhrase.ValidationError {
            rejection = error
        } catch {
            rejection = .invalidEntropy
        }
        rejectionCount += 1
        return false
    }

    /// Clears the entered words and passphrase and hides them.
    func clear() {
        phrase = ""
        passphrase = ""
        rejection = nil
        showsWords = false
        showsPassphrase = false
    }
}
