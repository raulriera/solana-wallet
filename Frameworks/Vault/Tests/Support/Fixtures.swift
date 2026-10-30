import Vault
import Wallet

enum Fixtures {
    static func recovery() throws -> Recovery {
        try Recovery(
            phrase: RecoveryPhrase(Array(repeating: "abandon", count: 11).joined(separator: " ") + " about"),
            passphrase: " TREZOR "
        )
    }
}
