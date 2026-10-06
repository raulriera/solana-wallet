import Foundation
import UIKit
import Wallet

/// Copies recovery words to a pasteboard that never shares them with other devices and clears them when they expire.
nonisolated struct RecoveryPasteboard: RecoveryCopying {
    let lifetime: Duration
    private let pasteboard: UIPasteboard

    /// Writes to one pasteboard with a fixed expiry.
    /// - Parameters:
    ///   - pasteboard: The destination; tests supply a named pasteboard.
    ///   - lifetime: How long copied words stay available to paste.
    init(pasteboard: UIPasteboard = .general, lifetime: Duration = .seconds(60)) {
        self.pasteboard = pasteboard
        self.lifetime = lifetime
    }

    /// Copies the words in their original order, separated by spaces, keeping them out of Universal Clipboard.
    /// - Parameter phrase: The recovery phrase shown for backup.
    func copy(_ phrase: RecoveryPhrase) {
        pasteboard.setObjects([phrase.words.joined(separator: " ")], localOnly: true,
                              expirationDate: .now.addingTimeInterval(lifetime / .seconds(1)))
    }
}
