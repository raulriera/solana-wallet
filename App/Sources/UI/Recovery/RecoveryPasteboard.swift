import Foundation
import UIKit
import Wallet

/// A pasteboard that keeps copied recovery words on this device and clears them when they expire.
nonisolated struct RecoveryPasteboard: RecoveryCopying {
    let lifetime: Duration
    private let pasteboard: UIPasteboard

    /// Creates a recovery pasteboard.
    ///
    /// - Parameters:
    ///   - pasteboard: The pasteboard to write to.
    ///   - lifetime: How long copied words stay available to paste.
    init(pasteboard: UIPasteboard = .general, lifetime: Duration = .seconds(60)) {
        self.pasteboard = pasteboard
        self.lifetime = lifetime
    }

    func copy(_ phrase: RecoveryPhrase) {
        pasteboard.setObjects([phrase.words.joined(separator: " ")], localOnly: true,
                              expirationDate: .now.addingTimeInterval(lifetime / .seconds(1)))
    }
}
