import Wallet
@testable import widgets

/// Accepts copies without touching any pasteboard.
nonisolated struct NoPasteboard: RecoveryCopying {
    let lifetime: Duration = .seconds(60)

    /// Ignores the copy.
    /// - Parameter phrase: The public test phrase.
    func copy(_ phrase: RecoveryPhrase) {}
}
