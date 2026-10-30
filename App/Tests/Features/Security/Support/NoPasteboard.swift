import Wallet
@testable import widgets

nonisolated struct NoPasteboard: RecoveryCopying {
    let lifetime: Duration = .seconds(60)

    func copy(_ phrase: RecoveryPhrase) {}
}
